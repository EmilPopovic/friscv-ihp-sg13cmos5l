# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
#
# Matej Jurasić <matej.jurasic@cappig.dev>


"""Characterise the delay-line macro and the pads into <work>/char/.

With the routed macro's .v and .sdf next to its .def, every corner is scaled to the
post-route typ delays.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from .config import CORNERS, Config
from .flow import FlowSettings, resolve, run_tcl, write_params
from .rtl import Controller


def run(cfg: Config, ctl: Controller, work: Path, what: str = "all", log=print) -> None:
    settings = resolve(cfg)
    out = Path(work) / "char"
    out.mkdir(parents=True, exist_ok=True)

    if what in ("all", "delay_line"):
        delay_line(cfg, ctl, settings, out, log)
    if what in ("all", "pads"):
        pads(cfg, settings, out, log)

    log(f"wrote {out}")


def delay_line(cfg: Config, ctl: Controller, settings: FlowSettings, out: Path, log) -> None:
    macro = Path(settings["macro"])
    codes = ctl.num_codes
    with_sdf = macro.with_suffix(".sdf").exists() and macro.with_suffix(".v").exists()
    select_pin = settings.get("macro_sel", "delay_i[{b}]")

    common = {
        "design": macro.name,
        "def": macro.with_suffix(".def"),
        "lefs": settings["lefs"],
        "rc_layer": settings["rc_layer"],
        "clk_in": settings.get("macro_clk_in", "clk_i"),
        "clk_out": settings.get("macro_clk_out", "clk_o*"),
        "sel_pins": [select_pin.format(b=b) for b in range(int(math.log2(codes)))],
        "n_codes": codes,
        "in_slew": settings.get("macro_in_slew", 0.1),
        "out_load": settings.get("macro_out_load", 0.02),
    }

    delays = {}
    for run_name in [*CORNERS, *(["sdf"] if with_sdf else [])]:
        corner = "typ" if run_name == "sdf" else run_name

        # the macro's own liberty would shadow the netlist being timed
        libs = [lib for lib in settings["libs"][corner] if Path(lib).stem != macro.name]

        params = {**common, "mode": "def", "libs": libs, "out": out / f"dline_{run_name}.txt"}
        if run_name == "sdf":
            params.update(mode="sdf", netlist=macro.with_suffix(".v"),
                          sdf=macro.with_suffix(".sdf"))

        log(f"  delay line, {run_name}")
        write_params(out / f"dline_{run_name}.tcl", params)
        run_tcl(cfg.tools.openroad, "delay_line_taps.tcl", out / f"dline_{run_name}.tcl")

        delays[run_name] = {int(c): (float(r), float(f)) for c, r, f in _data_lines(params["out"])}

    def tap(corner: str, code: int, edge: int) -> float:
        delay = delays[corner][code][edge]
        if with_sdf:
            delay *= delays["sdf"][code][edge] / delays["typ"][code][edge]
        return round(delay, 4)

    source = f"{macro.name}, OpenROAD on the DEF"
    if with_sdf:
        source += ", scaled to the post-route SDF"

    corners = {corner: {"rise": [tap(corner, code, 0) for code in range(codes)],
                        "fall": [tap(corner, code, 1) for code in range(codes)]}
               for corner in CORNERS}

    (out / "delay_line.json").write_text(json.dumps({"source": source, "corners": corners},
                                                    indent=1))


def pads(cfg: Config, settings: FlowSettings, out: Path, log) -> None:
    cells, pins = settings["pad_cells"], settings["pad_pins"]

    netlist = out / "pads.v"
    netlist.write_text(
        "module hb_pads (input c2p_io, input c2p_en_io, output p2c_io, inout pad_io, "
        "input c2p_o, inout pad_o);\n"
        f"    {cells['io']} i_io (.{pins['pad']}(pad_io), .{pins['c2p']}(c2p_io), "
        f".{pins['en']}(c2p_en_io), .{pins['p2c']}(p2c_io));\n"
        f"    {cells['out']} i_out (.{pins['pad']}(pad_o), .{pins['c2p']}(c2p_o));\n"
        "endmodule\n")

    loads = settings.get("pad_loads_pf", [2, 3, 5, 8, 10])
    slews = {"core_slew": settings.get("pad_core_slew", 0.15),
             "pad_slew": settings.get("pad_slew", 1.0)}
    table = {
        "source": f"{cells['out']} / {cells['io']}, OpenSTA, "
                  f"core slew {slews['core_slew']} ns, pad slew {slews['pad_slew']} ns",
        "loads_pf": loads,
        "corners": {},
    }

    for corner in CORNERS:
        log(f"  pads, {corner}")

        # only the pad library: the first one read sets the default thresholds
        libs = [lib for lib in settings["libs"][corner]
                if cells["io"] in Path(lib).read_text(errors="replace")]

        arcs = {arc: [] for arc in ("out", "io_out", "io_in", "io_en")}
        for load in loads:
            stem = out / f"pads_{corner}_{load}pF"
            write_params(stem.with_suffix(".tcl"), {
                "libs": libs, "netlist": netlist, "load_pf": load, **slews,
                "en_on": int(settings.get("pad_en_active_high", True)),
                "out": stem.with_suffix(".txt"),
            })
            run_tcl(cfg.tools.sta, "pad_delays.tcl", stem.with_suffix(".tcl"))

            for arc, rise, fall in _data_lines(stem.with_suffix(".txt")):
                arcs[arc].append([float(rise), float(fall)])

        table["corners"][corner] = arcs

    (out / "pads.json").write_text(json.dumps(table, indent=1))


def _data_lines(path) -> list[list[str]]:
    lines = Path(path).read_text().splitlines()
    return [line.split() for line in lines if line.strip() and not line.startswith("#")]
