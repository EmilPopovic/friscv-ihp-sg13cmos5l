# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
#
# Matej Jurasić <matej.jurasic@cappig.dev>


"""Delay line, pad, on-chip and HyperRAM timing, from built-in models or JSON tables.

Tables, in ns, per corner:

  delay line  {"source", "corners": {corner: {"rise": [per code], "fall": [...]}}}
  pads        {"source", "loads_pf": [...], "corners": {corner: {arc: [[rise, fall] per load]}}}
  on-chip     {"source", "corners": {corner: {"src": ..., <CHIP_FIELDS>: ns}}}
"""

from __future__ import annotations

import json
import tomllib
from dataclasses import dataclass
from pathlib import Path

from .config import CORNERS, TOOL_DIR, Config, ConfigError, Source
from .rtl import Controller

PAD_ARCS = ("out", "io_out", "io_in", "io_en")

# hbt_chip_delays_t (tb/hbt_pkg.sv) in struct order, typical of a 130 nm layout
ESTIMATE_TYP = {
    "dq_out_min": 1.40, "dq_out_max": 1.70, "dq_data_max": 1.95,
    "rwds_out_min": 1.40, "rwds_out_max": 1.70, "rwds_data_max": 1.95,
    "oe_min": 1.70, "oe_max": 2.10, "dl_tx_in": 1.00, "ck_out": 0.45,
    "cs_out_min": 0.70, "cs_out_max": 0.90, "rwds_in_dl": 0.20, "rx_icg": 0.05,
    "rx_pos_min": 1.60, "rx_pos_max": 1.90, "rx_neg_min": 1.70, "rx_neg_max": 2.10,
    "dq_in_min": 0.20, "dq_in_max": 0.60, "rws_in": 0.40, "l_core": 1.30, "ckq": 0.35,
    "cs_d_min": 1.80, "cs_d_max": 2.60, "ckena_d_min": 1.70, "ckena_d_max": 2.00,
    "rxena_d_min": 1.70, "rxena_d_max": 2.00,
    "ff_setup": 0.12, "ff_hold": 0.05, "icg_setup": 0.15, "icg_hold": 0.05,
}
CHIP_FIELDS = tuple(ESTIMATE_TYP)

# hbt_mem_profile_t, as in devices/hyperram.toml
DEVICE_FIELDS = (
    "tck_min", "tckhp_min", "tcshi", "trwr", "tcss", "tcsh", "tdsv_max", "tis", "tih", "tacc",
    "tckd_min", "tckd_max", "tckdi_min", "tckds_min", "tckds_max", "tdss", "tdsz_max",
    "toz_max", "tcsm_max", "tvcs", "die_bytes", "chip_bytes",
)

GENERATED_TABLES = {
    "delay_line": "char/delay_line.json",
    "pads": "char/pads.json",
    "chip": "extract/chip_delays.json",
}


@dataclass
class DelayLine:
    source: str
    rise: list[list[float]]  # [corner][code]
    fall: list[list[float]]

    def delay(self, corner: int, code: int) -> float:
        return max(self.rise[corner][code], self.fall[corner][code])


@dataclass
class Pads:
    source: str
    loads_pf: list[float]
    arcs: dict[str, list[list[list[float]]]]  # [corner][load][rise, fall]


@dataclass
class ChipDelays:
    sources: list[str]
    values: list[dict]


def delay_line(cfg: Config, ctl: Controller, work: Path) -> DelayLine:
    src = cfg.delay_line
    codes = ctl.num_codes

    if src.kind == "model":
        offset = src.params["offset_ns"]
        step = src.params["step_ns"]
        rise = [[offset[c] + step[c] * code for code in range(codes)] for c in range(len(CORNERS))]

        return DelayLine(f"linear model: {offset} + code x {step} ns", rise, [r[:] for r in rise])

    table, path = _read_table(src, work, "delay_line")
    rise, fall = [], []

    for corner in CORNERS:
        entry = table["corners"][corner]
        for edge in ("rise", "fall"):
            if len(entry[edge]) != codes:
                raise ConfigError(f"{path}: {len(entry[edge])} codes at {corner}, "
                                  f"the controller has {codes} taps")

        rise.append(entry["rise"])
        fall.append(entry["fall"])

    return DelayLine(table.get("source", str(path)), rise, fall)


def pads(cfg: Config, work: Path) -> Pads:
    src = cfg.pads

    if src.kind == "model":
        p = src.params
        arcs = {}
        for arc in PAD_ARCS:
            base, slope = p["base_ns"][arc], p["slope_ns_per_pf"][arc]
            arcs[arc] = [
                [[(base[edge] + slope[edge] * load) * scale for edge in (0, 1)]
                 for load in p["loads_pf"]]
                for scale in p["corner_scale"]
            ]

        return Pads("linear pad model", p["loads_pf"], arcs)

    table, path = _read_table(src, work, "pads")
    loads = table["loads_pf"]
    arcs = {arc: [table["corners"][corner][arc] for corner in CORNERS] for arc in PAD_ARCS}

    for arc, per_corner in arcs.items():
        if any(len(per_load) != len(loads) for per_load in per_corner):
            raise ConfigError(f"{path}: arc {arc} needs a value for each of the {len(loads)} loads")

    return Pads(table.get("source", str(path)), loads, arcs)


def chip_delays(cfg: Config, work: Path) -> ChipDelays:
    src = cfg.chip

    if src.kind == "model":
        unknown = sorted(set(src.params["typ"]) - set(CHIP_FIELDS))
        if unknown:
            raise ConfigError(f"chip.typ: unknown fields {', '.join(unknown)}")

        typ = {**ESTIMATE_TYP, **src.params["typ"]}
        scales = src.params["corner_scale"]

        return ChipDelays(
            sources=[f"ESTIMATE, typ x {s} ({corner})" for corner, s in zip(CORNERS, scales)],
            values=[{name: typ[name] * s for name in CHIP_FIELDS} for s in scales],
        )

    table, path = _read_table(src, work, "chip")
    sources, values = [], []

    for corner in CORNERS:
        entry = table["corners"][corner]
        missing = [name for name in CHIP_FIELDS if name not in entry]
        if missing:
            raise ConfigError(f"{path}: {corner} lacks {', '.join(missing)}")

        values.append({name: float(entry[name]) for name in CHIP_FIELDS})
        sources.append(entry.get("src", f"{table.get('source', path)} ({corner})"))

    return ChipDelays(sources, values)


def device_parts(cfg: Config) -> dict[str, dict]:
    """devices/hyperram.toml plus the config's [parts]."""
    database = tomllib.loads((TOOL_DIR / "devices" / "hyperram.toml").read_text())
    parts = {}

    for name, overrides in {**database.get("parts", {}), **cfg.parts}.items():
        unknown = sorted(set(overrides) - set(DEVICE_FIELDS))
        if unknown:
            raise ConfigError(f"device part {name}: unknown fields {', '.join(unknown)}")

        parts[name] = {**database["defaults"], **overrides}

    if cfg.device.part not in parts:
        known = ", ".join(sorted(parts))
        raise ConfigError(f"device {cfg.device.part} unknown; known parts: {known}")

    return parts


def _read_table(src: Source, work: Path, name: str) -> tuple[dict, Path]:
    path = src.file if src.kind == "table" else Path(work) / GENERATED_TABLES[name]

    try:
        table = json.loads(path.read_text())
    except FileNotFoundError:
        hint = "" if src.kind == "table" else f" (run `hbt {src.kind}` first)"
        raise ConfigError(f"{path} not found{hint}") from None

    missing = [c for c in CORNERS if c not in table.get("corners", {})]
    if missing:
        raise ConfigError(f"{path}: corners {', '.join(missing)} missing")

    return table, path
