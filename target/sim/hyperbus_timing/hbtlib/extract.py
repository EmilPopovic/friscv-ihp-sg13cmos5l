# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
#
# Matej Jurasić <matej.jurasic@cappig.dev>


"""On-chip HyperBus path delays from an OpenROAD database, into <work>/extract/.

Parasitics come from the run's SPEF for a routed database, else from global routing
([flow] guide) or placement.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from .config import CORNERS, Config, ConfigError
from .flow import resolve, run_tcl, write_params
from .rtl import Controller
from .timing import CHIP_FIELDS

# OpenSTA globs, first match wins; newer hyperbus versions keep more hierarchy
PHY_INSTANCES = {
    "tx_delay_line": ["*i_delay_tx_clk_90/i_delay.i_delay_line",
                      "*i_delay_tx_clk_90.i_delay.i_delay_line"],
    "rx_delay_line": ["*i_delay_rx_rwds_90/i_delay.i_delay_line",
                      "*i_delay_rx_rwds_90.i_delay.i_delay_line"],
    "ck_gate": ["*i_clock_diff_out/i_hyper_ck_gating.i_clkgate", "*i_hyper_ck_gating.i_clkgate"],
    "rx_gate": ["*i_rwds_in_clk_gate/i_clkgate", "*i_rwds_in_clk_gate.i_clkgate"],
}

LIB_CHECKS = (("ff", "flop"), ("icg", "icg"))


def run(cfg: Config, ctl: Controller, work: Path, odb: str | None = None,
        run_dir: str | None = None, log=print) -> None:
    settings = resolve(cfg, run=run_dir, odb=odb)
    database = Path(settings["odb"])
    ports, pins = settings["ports"], settings["pins"]

    missing = [name for name in ("dq", "rwds", "ck", "cs") if name not in ports]
    if missing:
        raise ConfigError(f"[flow] ports needs {', '.join(missing)}")

    instances = dict(PHY_INSTANCES)
    for key, value in settings.get("phy", {}).items():
        instances[key] = [value] if isinstance(value, str) else value

    def pin_patterns(instance: str, pin: str) -> list[str]:
        return [f"{pattern}/{pin}" for pattern in instances[instance]]

    params = {
        "odb": database,
        "guide": settings.get("guide", ""),
        "layer_rc": [" ".join(map(str, layer)) for layer in settings.get("layer_rc", [])],
        "signal_layers": settings["signal_layers"],
        "clock_layers": settings["clock_layers"],
        "clock_root": settings.get("clock_root", ""),
        "clock_port": settings["clock_port"],
        "period": cfg.period_ns,
        "cs_clock": ctl.cs_clock,
        **{f"{name}_port": pattern for name, pattern in ports.items()},
        **{f"pad_{name}": pin for name, pin in settings["pad_pins"].items()},
        "tx_dl_in": pin_patterns("tx_delay_line", "clk_i"),
        "tx_dl_out": pin_patterns("tx_delay_line", "clk_o*"),
        "rx_dl_in": pin_patterns("rx_delay_line", "clk_i"),
        "rx_dl_out": pin_patterns("rx_delay_line", "clk_o*"),
        "ck_gate_en": pin_patterns("ck_gate", pins["icg_en"]),
        "rx_gate_en": pin_patterns("rx_gate", pins["icg_en"]),
        "rx_gate_clk": pin_patterns("rx_gate", pins["icg_clk"]),
        **{f"cell_{kind}": globs for kind, globs in settings["cells"].items()},
        **{f"pin_{name}": pin for name, pin in pins.items()},
    }

    out = Path(work) / "extract"
    out.mkdir(parents=True, exist_ok=True)

    spef = settings.get("spef", {})
    step = f"{database.parent.parent.name}/{database.parent.name}"
    table = {"source": f"{step}/{database.name}", "corners": {}}

    for corner in CORNERS:
        libs = settings["libs"][corner]
        result = out / f"chip_delays_{corner}.txt"
        script = out / f"chip_delays_{corner}.tcl"
        write_params(script, {**params, "libs": libs, "spef": spef.get(corner, ""), "out": result})

        if corner in spef:
            parasitics = "SPEF"
        else:
            parasitics = "global-route" if params["guide"] else "placement"
        log(f"  {corner}: {parasitics} parasitics, {step}")

        run_tcl(cfg.tools.openroad, "extract_chip_delays.tcl", script)
        table["corners"][corner] = _corner_entry(result, step, corner, libs, settings["lib_check"])

    (out / "chip_delays.json").write_text(json.dumps(table, indent=1))
    log(f"wrote {out / 'chip_delays.json'}")


def _corner_entry(result: Path, step: str, corner: str, libs: list[str], lib_check: dict) -> dict:
    header, *lines = result.read_text().splitlines()
    parasitics = header[2:].split(",")[0].replace("parasitics: ", "")
    measured = {}
    for line in lines:
        path, low, high = line.split()
        measured[path] = (float(low), float(high))

    entry = {"src": f"P&R {step}, {parasitics} ({corner})"}

    for field in CHIP_FIELDS:
        if not field.startswith(("ff_", "icg_")):
            path, index = _measured_path(field)
            entry[field] = round(measured[path][index], 4)

    for prefix, key in LIB_CHECKS:
        for kind in ("setup", "hold"):
            check = liberty_check(libs, lib_check[key], f"{kind}_rising")
            entry[f"{prefix}_{kind}"] = round(check, 4)

    return entry


def _measured_path(field: str) -> tuple[str, int]:
    if field.endswith("_min"):
        return field.removesuffix("_min"), 0
    if field.endswith("_max"):
        return field.removesuffix("_max"), 1

    return field, 1


def liberty_check(libs: list[str], cell_pattern: str, kind: str) -> float:
    """The worst mid-table setup or hold time of a sequential cell."""
    cell_re = re.compile(r'cell\s*\(\s*"?(' + cell_pattern + r')"?\s*\)')
    arc_re = re.compile(r"timing\s*\(\s*\)\s*\{(.*?)\n\s{6,8}\}", re.S)
    kind_re = re.compile(rf'timing_type\s*:\s*"?{kind}"?')
    table_re = re.compile(r"(rise|fall)_constraint.*?values\s*\((.*?)\);", re.S)
    number_re = re.compile(r"-?[0-9.]+(?:e-?\d+)?")

    for lib in libs:
        text = Path(lib).read_text(errors="replace")
        cell = cell_re.search(text)
        if not cell:
            continue

        body = text[cell.end():text.find("\n  cell", cell.end())]
        values = []

        for arc in arc_re.finditer(body):
            if not kind_re.search(arc.group(1)):
                continue

            for table in table_re.finditer(arc.group(1)):
                numbers = [float(n) for n in number_re.findall(table.group(2))]
                values.append(numbers[len(numbers) // 2])

        if values:
            return max(values)

    raise ConfigError(f"no {kind} tables for a cell matching {cell_pattern} "
                      "in the corner's liberty files")
