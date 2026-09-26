# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
#
# Matej Jurasić <matej.jurasic@cappig.dev>


"""Stress one tap pair and scan each physical parameter until it fails.

Every case runs at every corner and device variant. Writes <work>/check/check.{txt,json}.
"""

from __future__ import annotations

import json
import math
import os
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from . import build, timing
from .analysis import row_causes
from .config import Config
from .rtl import Controller
from .sweep import device_variants, simulate

PROBE_BURST_MAX = 100
MIN_PERIOD_NS = 8.0
TCSM_MARGIN = 0.95


@dataclass
class Case:
    label: str
    args: list[str]
    runs: list[dict | None] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return all(run is not None and run["status"] == "PASS" for run in self.runs)

    def worst(self, corner: str) -> str:
        runs = [run for run in self.runs if run is None or run["corner"] == corner]
        if any(run is None for run in runs):
            return "ERROR"

        failed = [run for run in runs if run["status"] != "PASS"]
        if failed:
            causes = set().union(*(row_causes(run) for run in failed))
            return "FAIL " + ",".join(sorted(causes))

        return f"{min(run['worst'] for run in runs):+.2f}"

    def cs_low_max(self) -> float:
        return max(run["cs_low_max"] for run in self.runs if run is not None)


@dataclass
class Scan:
    label: str
    unit: str
    values: list[float]
    nominal: float
    args: Callable[[float], list[str]]
    cases: list[Case] = field(default_factory=list)

    def limits(self) -> tuple[float | None, float | None]:
        passed = {value: case.passed for value, case in zip(self.values, self.cases)}
        below = sorted((v for v in self.values if v <= self.nominal), reverse=True)
        above = [v for v in self.values if v >= self.nominal]

        return _last_passing(below, passed), _last_passing(above, passed)


def _last_passing(values: list[float], passed: dict) -> float | None:
    last = None

    for value in values:
        if not passed[value]:
            break
        last = value

    return last


class _Runner:
    def __init__(self, binary, base, corners, variants, timeout_s, jobs):
        self.binary = binary
        self.base = base
        self.corners = corners
        self.variants = variants
        self.timeout_s = timeout_s
        self.jobs = jobs

    def run(self, cases: list[Case]) -> list[Case]:
        jobs = [(case, corner, variant)
                for case in cases for corner in self.corners for variant in self.variants]

        with ThreadPoolExecutor(self.jobs) as pool:
            for (case, _, _), result in zip(jobs, pool.map(lambda job: self._one(*job), jobs)):
                case.runs.append(result)

        return cases

    def _one(self, case: Case, corner: str, variant: str) -> dict | None:
        # $value$plusargs takes the first match, so later arguments replace earlier ones here
        merged = {}
        for arg in (f"+corner={corner}", *self.base, *variant.split(), *case.args):
            merged[arg.split("=", 1)[0]] = arg

        return simulate(self.binary, list(merged.values()), self.timeout_s)


def run(cfg: Config, ctl: Controller, work: Path, *, pair=None, jobs=None, log=print) -> bool:
    fast_binary = build.build(cfg, ctl, work, fast=True, min_period_ns=MIN_PERIOD_NS, log=log)
    full_binary = build.build(cfg, ctl, work, fast=False, log=log)

    tx, rx = pair or ctl.reset_codes(cfg.rst_cfg)
    base = [f"+tx_code={tx}", f"+rx_code={rx}", f"+seed={cfg.sweep.seed}",
            f"+n_txn={cfg.sweep.n_txn}"]
    corners = cfg.sweep.corners
    variants = device_variants(cfg)
    jobs = jobs or cfg.sweep.jobs or os.cpu_count()
    runner = _Runner(fast_binary, base, corners, variants, cfg.sweep.timeout_s, jobs)

    tcsm = _BurstLimit(cfg, runner)
    log(f"checking TX {tx} / RX {rx}: CS# low overhead {tcsm.overhead:.1f} clocks, "
        f"safe t_burst_max {tcsm.at(cfg.period_ns)} at {cfg.period_ns} ns")

    stress = runner.run(_stress_cases(cfg, tcsm))

    # a full power-up is slow and the same for every device variant
    power_up = _Runner(full_binary, base, corners, variants[:1], cfg.sweep.timeout_s, jobs)
    stress += power_up.run([Case("full power-up", [])])

    scans = _scans(cfg, tcsm)
    for scan in scans:
        scan.cases = runner.run([Case(f"{scan.label} {v:g}", scan.args(v)) for v in scan.values])

    passed = all(case.passed for case in stress)

    out = Path(work) / "check"
    out.mkdir(parents=True, exist_ok=True)

    text = _text(cfg, tx, rx, corners, stress, scans, tcsm, passed)
    (out / "check.txt").write_text(text)
    summary = _summary(cfg, tx, rx, corners, stress, scans, tcsm, passed)
    (out / "check.json").write_text(json.dumps(summary, indent=1) + "\n")

    log(text, end="")
    log(f"written to {out}")

    return passed


class _BurstLimit:
    """Largest t_burst_max keeping CS# low under tCSM: t_burst_max clocks plus an overhead
    measured once, with bursts cut at PROBE_BURST_MAX."""

    def __init__(self, cfg: Config, runner: _Runner):
        self.tcsm = timing.device_parts(cfg)[cfg.device.part]["tcsm_max"]
        self.min_period = 1000.0 / cfg.min_freq_mhz

        probe = Case("probe", ["+long_bursts=1", f"+t_burst_max={PROBE_BURST_MAX}"])
        runner.run([probe])
        self.probe_cs_low = probe.cs_low_max()
        self.overhead = self.probe_cs_low / cfg.period_ns - PROBE_BURST_MAX

    def at(self, period_ns: float) -> int:
        return max(1, math.floor(TCSM_MARGIN * self.tcsm / period_ns - self.overhead))


def _stress_cases(cfg: Config, tcsm: _BurstLimit) -> list[Case]:
    traffic = 4 * cfg.sweep.n_txn
    cases = [Case(f"seed {seed}, {traffic} transactions", [f"+seed={seed}", f"+n_txn={traffic}"])
             for seed in range(1, cfg.check.seeds + 1)]

    burst_max = tcsm.at(cfg.period_ns)
    cases.append(Case(f"long bursts, t_burst_max {burst_max}",
                      ["+long_bursts=4", f"+t_burst_max={burst_max}"]))
    cases.append(Case("variable latency, refresh on every access",
                      ["+mem_fixed=0", "+refresh_pct=100"]))

    slowest = tcsm.min_period
    slow_burst_max = tcsm.at(slowest)
    cases.append(Case(f"{1000 / slowest:g} MHz, t_burst_max {slow_burst_max}",
                      [f"+tck_ns={slowest}", f"+t_burst_max={slow_burst_max}"]))

    return cases + _stacked(cfg)


def _stacked(cfg: Config) -> list[Case]:
    check = cfg.check
    skew = cfg.board.skew_ns
    cases = []

    for pattern, direction in ((1, "setup"), (2, "hold")):
        for load in check.load_pf:
            for duty in check.duty:
                label = (f"stacked {direction}: {load:g} pF, duty {duty:g}, skew {skew:g} ns, "
                         f"OCV {100 * check.ocv:g} %")
                cases.append(Case(label, [f"+load_pf={load:g}", f"+duty={duty:g}",
                                          f"+skew_pattern={pattern}", f"+flight_skew_ns={skew:g}",
                                          f"+ocv={check.ocv:g}", f"+ocv_pattern={pattern}"]))

    return cases


def _scans(cfg: Config, tcsm: _BurstLimit) -> list[Scan]:
    board = cfg.board
    period = cfg.period_ns
    periods = sorted({*_steps(MIN_PERIOD_NS, 30.0, 0.5), period})

    return [
        Scan("clk duty at the pad", "", _steps(0.40, 0.60, 0.01), 0.5,
             lambda v: [f"+duty={v:g}"]),
        Scan("pin load", "pF", _steps(2.0, 10.0, 1.0), board.load_pf,
             lambda v: [f"+load_pf={v:g}"]),
        Scan("trace delay", "ns", _steps(0.0, 2.0, 0.25), board.flight_ns,
             lambda v: [f"+flight_ns={v:g}"]),
        Scan("net skew, data late", "ns", _steps(0.0, 1.0, 0.05), 0.0,
             lambda v: [f"+flight_skew_ns={v:g}", "+skew_pattern=1"]),
        Scan("net skew, data early", "ns", _steps(0.0, 1.0, 0.05), 0.0,
             lambda v: [f"+flight_skew_ns={v:g}", "+skew_pattern=2"]),
        Scan("on-chip variation, setup", "%", _steps(0, 20, 1), 0,
             lambda v: [f"+ocv={v / 100:g}", "+ocv_pattern=1"]),
        Scan("on-chip variation, hold", "%", _steps(0, 20, 1), 0,
             lambda v: [f"+ocv={v / 100:g}", "+ocv_pattern=2"]),
        Scan("clock jitter", "ns", _steps(0.0, 1.0, 0.05), board.jitter_ns,
             lambda v: [f"+jitter_ns={v:g}"]),
        Scan("clock period", "ns", periods, period,
             lambda v: [f"+tck_ns={v:g}", f"+t_burst_max={tcsm.at(v)}"]),
    ]


def _steps(low: float, high: float, step: float) -> list[float]:
    count = int(round((high - low) / step)) + 1
    return [round(low + i * step, 6) for i in range(count)]


def _text(cfg, tx, rx, corners, stress, scans, tcsm, passed) -> str:
    cells = [[case.worst(corner) for corner in corners] for case in stress]
    label_width = max(len(case.label) for case in stress) + 2
    cell_width = max(len(cell) for row in cells for cell in row) + 3

    lines = [f"{cfg.name}: TX {tx} / RX {rx}, {cfg.device.part}, {cfg.period_ns} ns", ""]
    lines.append("stress".ljust(label_width) + "".join(c.rjust(cell_width) for c in corners))
    for case, row in zip(stress, cells):
        lines.append(case.label.ljust(label_width) + "".join(c.rjust(cell_width) for c in row))

    lines += ["", "limits (every corner and variant still passes)"]
    lines += [f"  {scan.label:<28}{_limits_text(scan)}" for scan in scans]

    slowest = tcsm.min_period
    lines += [
        "",
        f"tCSM {tcsm.tcsm:g} ns: CS# low {tcsm.probe_cs_low:.0f} ns at t_burst_max "
        f"{PROBE_BURST_MAX}; use t_burst_max <= {tcsm.at(cfg.period_ns)} at {cfg.period_ns} ns, "
        f"<= {tcsm.at(slowest)} at {slowest:g} ns",
        "",
        "PASS" if passed else "FAIL",
    ]

    return "\n".join(lines) + "\n"


def _limits_text(scan: Scan) -> str:
    low, high = scan.limits()
    if low is None or high is None:
        return "fails at nominal"

    unit = f" {scan.unit}" if scan.unit else ""
    text = f"{low:g} .. {high:g}{unit}"

    first, last = scan.values[0], scan.values[-1]
    if low == first or high == last:
        text += f" (scanned {first:g} .. {last:g})"

    return text


def _summary(cfg, tx, rx, corners, stress, scans, tcsm, passed) -> dict:
    def per_corner(case):
        return {corner: case.worst(corner) for corner in corners}

    limits = {}
    for scan in scans:
        low, high = scan.limits()
        limits[scan.label] = {"low": low, "high": high}

    return {
        "system": cfg.name,
        "tx": tx,
        "rx": rx,
        "pass": passed,
        "stress": {case.label: per_corner(case) for case in stress},
        "limits": limits,
        "scans": {scan.label: {f"{v:g}": per_corner(c) for v, c in zip(scan.values, scan.cases)}
                  for scan in scans},
        "t_burst_max": {
            "cs_low_overhead_clocks": round(tcsm.overhead, 1),
            "at_period": tcsm.at(cfg.period_ns),
            "at_min_freq": tcsm.at(tcsm.min_period),
        },
    }
