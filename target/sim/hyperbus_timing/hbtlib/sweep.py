# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
#
# Matej Jurasić <matej.jurasic@cappig.dev>


"""Simulate corners x TX taps x RX taps x device variants into <work>/sweep/<tag>.{csv,json}."""

from __future__ import annotations

import csv
import datetime
import json
import os
import re
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

from . import build, timing
from .config import CORNERS, REPO_ROOT, Config
from .rtl import Controller

SLACKS = ("mem_su", "mem_ho", "rx_su", "rx_ho", "rws_su", "rws_ho", "int_su", "int_ho")
COUNTS = ("timing_vio", "mem_vio", "mism", "hang", "cont", "reads", "writes")
COLUMNS = ("corner", "tx", "rx", "variant", "seed", "status", "worst", *SLACKS, *COUNTS,
           "cs_low_max", "mem", "tckds", "rwds_mode")
DEVICE_TIMING = ("tis", "tih", "tdss", "tckds_min", "tckds_max", "tcsm_max")
FAILED_RUN_SLACK = -1e9


@dataclass(frozen=True)
class Point:
    corner: str
    tx: int
    rx: int
    variant: str


def parse_codes(spec: str, num_codes: int) -> list[int]:
    """"all", "0-15", "3,5,7" or "all:2" (every second code)."""
    codes = []

    for part in str(spec or "all").split(","):
        span, _, step = part.partition(":")
        if span in ("all", ""):
            span = f"0-{num_codes - 1}"

        low, _, high = span.partition("-")
        codes += range(int(low), int(high or low) + 1, int(step or 1))

    outside = [c for c in codes if not 0 <= c < num_codes]
    if outside:
        raise ValueError(f"tap codes {outside} are outside the delay line's 0..{num_codes - 1}")

    return codes


def device_variants(cfg: Config) -> list[str]:
    """Both CK-to-RWDS extremes, and the RWDS levels the datasheets leave open."""
    if cfg.sweep.variants != "auto":
        return list(cfg.sweep.variants)

    part = timing.device_parts(cfg)[cfg.device.part]
    slow, fast = part["tckds_max"], part["tckds_min"]

    return [
        f"+mem_tckds={slow:g} +rwds_mode=0",
        f"+mem_tckds={fast:g} +rwds_mode=0",
        f"+mem_tckds={slow:g} +rwds_mode=1 +skew_pattern=1",
        f"+mem_tckds={fast:g} +rwds_mode=2 +skew_pattern=2",
    ]


def sweep(cfg: Config, ctl: Controller, work: Path, binary: Path, *, corners=None, tx=None,
          rx=None, jobs=None, tag="sweep", extra="", log=print) -> None:
    corners = corners or cfg.sweep.corners
    tx_codes = parse_codes(tx or cfg.sweep.tx, ctl.num_codes)
    rx_codes = parse_codes(rx or cfg.sweep.rx, ctl.num_codes)
    if cfg.clock != "delayed":
        tx_codes = [ctl.reset_codes(cfg.rst_cfg)[0]]  # no TX delay line

    variants = device_variants(cfg)
    jobs = jobs or cfg.sweep.jobs or os.cpu_count()
    points = [Point(c, t, r, v)
              for c in corners for t in tx_codes for r in rx_codes for v in variants]

    log(f"{len(points)} simulations: {len(corners)} corners x {len(tx_codes)} TX x "
        f"{len(rx_codes)} RX x {len(variants)} device variants, {jobs} at a time")

    started = time.time()
    every = max(1, len(points) // 20)
    rows = []

    with ThreadPoolExecutor(jobs) as pool:
        futures = [pool.submit(_simulate, binary, p, cfg, extra) for p in points]
        for done, future in enumerate(futures, 1):
            rows.append(future.result())
            if done % every == 0:
                elapsed = time.time() - started
                left = elapsed / done * (len(points) - done)
                log(f"  {done}/{len(points)}, {elapsed:.0f} s, about {left:.0f} s left")

    out = Path(work) / "sweep"
    out.mkdir(parents=True, exist_ok=True)

    with open(out / f"{tag}.csv", "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=COLUMNS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)

    meta = _metadata(cfg, ctl, work, corners, tx_codes, rx_codes, variants, time.time() - started)
    (out / f"{tag}.json").write_text(json.dumps(meta, indent=1))


def load(work: Path, tag: str = "sweep") -> tuple[dict, list[dict]]:
    out = Path(work) / "sweep"

    try:
        meta = json.loads((out / f"{tag}.json").read_text())
        with open(out / f"{tag}.csv", newline="") as fh:
            rows = [_parse_row(row) for row in csv.DictReader(fh)]
    except FileNotFoundError as err:
        raise FileNotFoundError(f"no sweep '{tag}' in {out} ({err.filename} missing)") from None

    return meta, rows


def simulate(binary: Path, plusargs: list[str], timeout_s: int) -> dict | None:
    """The HBT_RESULT fields; None if the run crashed or timed out."""
    try:
        result = subprocess.run([str(binary), "+max_msgs=0", *plusargs], capture_output=True,
                                text=True, timeout=timeout_s, cwd=binary.parent)
    except subprocess.TimeoutExpired:
        return None

    line = re.search(r"^HBT_RESULT (.*)$", result.stdout, re.M)
    if not line:
        return None

    row = _parse_row(dict(pair.split("=", 1) for pair in line.group(1).split()))
    row["worst"] = min(row[key] for key in SLACKS)

    return row


def _simulate(binary: Path, point: Point, cfg: Config, extra: str) -> dict:
    plusargs = [f"+corner={point.corner}", f"+tx_code={point.tx}", f"+rx_code={point.rx}",
                f"+n_txn={cfg.sweep.n_txn}", f"+seed={cfg.sweep.seed}",
                *point.variant.split(), *extra.split()]
    row = {"corner": point.corner, "tx": point.tx, "rx": point.rx, "variant": point.variant,
           "seed": cfg.sweep.seed}

    result = simulate(binary, plusargs, cfg.sweep.timeout_s)
    if result is None:
        return {**row, "status": "ERROR", "worst": f"{FAILED_RUN_SLACK:g}"}

    return {**result, **row, "worst": f"{result['worst']:.3f}"}


def _parse_row(row: dict) -> dict:
    parsed = dict(row)
    parsed["tx"] = int(row["tx"])
    parsed["rx"] = int(row["rx"])
    parsed["worst"] = _number(row.get("worst"), FAILED_RUN_SLACK)
    parsed["cs_low_max"] = _number(row.get("cs_low_max"), 0.0)

    for key in SLACKS:
        parsed[key] = _number(row.get(key), FAILED_RUN_SLACK)
    for key in COUNTS:
        parsed[key] = int(_number(row.get(key), 0))

    return parsed


def _number(value, default: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _metadata(cfg, ctl, work, corners, tx_codes, rx_codes, variants, elapsed_s) -> dict:
    delay = timing.delay_line(cfg, ctl, work)
    device = timing.device_parts(cfg)[cfg.device.part]
    chip = timing.chip_delays(cfg, work)
    reset_tx, reset_rx = ctl.reset_codes(cfg.rst_cfg)

    return {
        "system": cfg.name,
        "config": str(cfg.path.relative_to(REPO_ROOT)),
        "date": datetime.datetime.now().isoformat(timespec="seconds"),
        "controller": ctl.summary(),
        "clocking": cfg.clock,
        "period_ns": cfg.period_ns,
        "device": cfg.device.part,
        "device_timing": {key: device[key] for key in DEVICE_TIMING},
        "corners": corners,
        "tx": tx_codes,
        "rx": rx_codes,
        "variants": variants,
        "reset": {"tx": reset_tx, "rx": reset_rx},
        "n_txn": cfg.sweep.n_txn,
        "delay_line": {"corners": list(CORNERS), "rise": delay.rise, "fall": delay.fall},
        "sources": {
            "delay_line": delay.source,
            "pads": timing.pads(cfg, work).source,
            "chip": chip.sources[CORNERS.index("typ")],
        },
        "verilator": build.verilator_version(cfg),
        "commit": _commit(),
        "elapsed_s": round(elapsed_s, 1),
    }


def _commit() -> str:
    result = subprocess.run(["git", "describe", "--always", "--dirty", "--abbrev=12"],
                            cwd=REPO_ROOT, capture_output=True, text=True)
    return result.stdout.strip() or "unknown"
