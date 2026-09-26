# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
#
# Matej Jurasić <matej.jurasic@cappig.dev>

"""Timing simulation of a HyperBus interface built on the PULP hyperbus controller.

Run inside `nix develop` at the repository root. sweep, report and all exit
with 0 if a tap pair passes at every corner (and the reset taps pass, with
--require-reset), 2 if not, and 1 on errors.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys

from . import build, config, report, rtl, sweep, timing
from .config import ConfigError

TOOL_OVERRIDES = ("verilator", "bender", "openroad", "sta")


def main(argv=None) -> int:
    args = _parser().parse_args(argv)

    try:
        return args.command(args)
    except (ConfigError, rtl.RtlError, build.BuildError, ValueError, FileNotFoundError) as err:
        print(f"hbt: error: {err}", file=sys.stderr)
        return 1


def _load(args):
    cfg = config.load(args.config)

    for tool in TOOL_OVERRIDES:
        override = os.environ.get(f"HBT_{tool.upper()}")
        if override:
            setattr(cfg.tools, tool, override)

    if args.vjobs is not None:
        cfg.tools.vjobs = args.vjobs

    return cfg, rtl.detect(cfg.hyperbus), config.work_dir(cfg, args.work)


def cmd_detect(args) -> int:
    cfg, ctl, work = _load(args)
    print(ctl.summary())
    print(f"  work directory: {work}")

    def show_source(name, read_source):
        try:
            print(f"  {name}: {read_source()}")
        except ConfigError as err:
            print(f"  {name}: not available ({err})")

    show_source("delay line", lambda: timing.delay_line(cfg, ctl, work).source)
    show_source("pads", lambda: timing.pads(cfg, work).source)
    show_source("on-chip", lambda: timing.chip_delays(cfg, work).sources[1])

    print(f"  device: {cfg.device.part}")
    for variant in sweep.device_variants(cfg):
        print(f"    variant {variant}")

    return 0


def cmd_build(args) -> int:
    cfg, ctl, work = _load(args)
    build.build(cfg, ctl, work, fast=args.fast, force=args.force)
    return 0


def cmd_run(args) -> int:
    cfg, ctl, work = _load(args)
    binary = build.build(cfg, ctl, work, fast=args.fast)
    return subprocess.run([str(binary), *args.plusargs], cwd=binary.parent).returncode


def cmd_sweep(args) -> int:
    cfg, ctl, work = _load(args)
    if args.n_txn:
        cfg.sweep.n_txn = args.n_txn

    binary = build.build(cfg, ctl, work, fast=True)
    corners = args.corners.split(",") if args.corners else None
    sweep.sweep(cfg, ctl, work, binary, corners=corners, tx=args.tx, rx=args.rx,
                jobs=args.jobs, tag=args.tag, extra=args.extra)

    return _report(work, args.tag, args.require_reset)


def cmd_report(args) -> int:
    _, _, work = _load(args)
    return _report(work, args.tag, args.require_reset)


def cmd_check(args) -> int:
    from . import check

    cfg, ctl, work = _load(args)
    reset_tx, reset_rx = ctl.reset_codes(cfg.rst_cfg)
    tx = args.tx if args.tx is not None else reset_tx
    rx = args.rx if args.rx is not None else reset_rx

    return 0 if check.run(cfg, ctl, work, pair=(tx, rx), jobs=args.jobs) else 2


def cmd_char(args) -> int:
    from . import char

    cfg, ctl, work = _load(args)
    char.run(cfg, ctl, work, what=args.what)
    return 0


def cmd_extract(args) -> int:
    from . import extract

    cfg, ctl, work = _load(args)
    extract.run(cfg, ctl, work, odb=args.odb, run_dir=args.run)
    return 0


def cmd_all(args) -> int:
    cfg, ctl, work = _load(args)

    if "char" in (cfg.delay_line.kind, cfg.pads.kind):
        from . import char
        char.run(cfg, ctl, work)

    if cfg.chip.kind == "extract":
        from . import extract
        extract.run(cfg, ctl, work)

    return cmd_sweep(args)


def _report(work, tag: str, require_reset: bool) -> int:
    meta, rows = sweep.load(work, tag)
    analysis, summary, text_path = report.write(meta, rows, work, tag)

    print(report.text(meta, analysis, summary), end="")
    print(f"report: {text_path}")

    passed = summary["pass"] and (summary["reset"]["pass"] or not require_reset)
    return 0 if passed else 2


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="hbt", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--work", help="work directory (default: work/<system name>)")
    parser.add_argument("--vjobs", type=int, help="Verilator build jobs")

    commands = parser.add_subparsers(dest="name", required=True, metavar="command")

    def command(name, function, summary):
        sub = commands.add_parser(name, help=summary, description=summary)
        sub.add_argument("config", help="system config, e.g. configs/vernii.toml")
        sub.set_defaults(command=function)
        return sub

    command("detect", cmd_detect, "show what the controller RTL and the config resolve to")

    sub = command("build", cmd_build, "generate and compile the testbench")
    sub.add_argument("--fast", action="store_true", help="short PHY start-up, as sweeps use")
    sub.add_argument("--force", action="store_true", help="rebuild even if up to date")

    sub = command("run", cmd_run, "run one simulation")
    sub.add_argument("--fast", action="store_true", help="short PHY start-up")
    sub.add_argument("plusargs", nargs="*",
                     help="e.g. +corner=slow +tx_code=9 +rx_code=12 +verbose +trace_bus=4")

    def sweep_options(sub):
        sub.add_argument("--corners", help="comma-separated, e.g. fast,slow")
        sub.add_argument("--tx", help="TX tap codes, e.g. all, 0-7, 3,5,9 or all:2")
        sub.add_argument("--rx", help="RX tap codes")
        sub.add_argument("--jobs", type=int, help="parallel simulations")
        sub.add_argument("--n-txn", type=int, help="transactions per simulation")
        sub.add_argument("--extra", default="", help="plusargs added to every simulation")
        sub.add_argument("--tag", default="sweep", help="name of the result files")
        sub.add_argument("--require-reset", action="store_true",
                         help="exit 2 unless the reset taps pass")

    sweep_options(command("sweep", cmd_sweep, "sweep the tap codes and write the report"))
    sweep_options(command("all", cmd_all, "char and extract as configured, then sweep"))

    sub = command("check", cmd_check, "stress one tap pair and find its limits")
    sub.add_argument("--tx", type=int, help="TX tap code (default: the reset value)")
    sub.add_argument("--rx", type=int, help="RX tap code")
    sub.add_argument("--jobs", type=int, help="parallel simulations")

    sub = command("report", cmd_report, "rewrite the report of an earlier sweep")
    sub.add_argument("--tag", default="sweep")
    sub.add_argument("--require-reset", action="store_true")

    sub = command("char", cmd_char, "characterise the delay line and the pads")
    sub.add_argument("--what", choices=("delay_line", "pads", "all"), default="all")

    sub = command("extract", cmd_extract, "extract the on-chip delays from a P&R database")
    sub.add_argument("--odb", help="database (default: the latest in the run)")
    sub.add_argument("--run", help="LibreLane run directory (default: [flow] run)")

    return parser
