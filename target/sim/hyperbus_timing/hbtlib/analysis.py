# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
#
# Matej Jurasić <matej.jurasic@cappig.dev>


"""Pass maps, margins and the recommended tap pair of a sweep.

A point (corner, TX, RX) passes when every device variant passes at it. The
recommended pair passes at every corner with the largest smallest margin.
"""

from __future__ import annotations

from dataclasses import dataclass, field

GROUPS = (("mem", "device balls"), ("rx", "RX capture"), ("rws", "latency sample"),
          ("int", "internal"))
CAUSES = ("device", "RX capture", "latency sample", "internal", "data", "hang", "contention",
          "simulation error")
COUNTED_CAUSES = (("hang", "hang"), ("contention", "cont"), ("data", "mism"))


@dataclass
class PointResult:
    passed: bool
    worst: float
    margins: dict[str, tuple[float, float]]  # group -> (setup, hold)
    causes: set[str]
    cs_low_max: float


@dataclass
class Analysis:
    corners: list[str]
    tx: list[int]
    rx: list[int]
    reset: tuple[int, int]
    points: dict[tuple[str, int, int], PointResult]
    common: list[tuple[int, int]]
    recommended: tuple[int, int] | None
    best_per_corner: dict[str, tuple[int, int] | None]
    passing_per_corner: dict[str, int]
    by_variant: dict[tuple[str, str], tuple[int, int, dict[str, int]]] = field(default_factory=dict)

    def point(self, corner: str, tx: int, rx: int) -> PointResult | None:
        return self.points.get((corner, tx, rx))

    def passes(self, corner: str, tx: int, rx: int) -> bool:
        point = self.point(corner, tx, rx)
        return point is not None and point.passed

    def worst_over_corners(self, pair: tuple[int, int]) -> float:
        tx, rx = pair
        return min(self.points[(corner, tx, rx)].worst for corner in self.corners)

    def reset_passes(self) -> bool:
        return all(self.passes(corner, *self.reset) for corner in self.corners)


def row_causes(row: dict) -> set[str]:
    if row["status"] == "PASS":
        return set()
    if row["status"] == "ERROR":
        return {"simulation error"}

    causes = {cause for cause, counter in COUNTED_CAUSES if row[counter]}

    if min(row["mem_su"], row["mem_ho"]) < 0 or row["mem_vio"]:
        causes.add("device")

    for key, label in GROUPS[1:]:
        if min(row[f"{key}_su"], row[f"{key}_ho"]) < 0:
            causes.add(label)

    return causes


def analyse(meta: dict, rows: list[dict]) -> Analysis:
    corners, tx_codes, rx_codes = meta["corners"], meta["tx"], meta["rx"]
    reset = (meta["reset"]["tx"], meta["reset"]["rx"])

    runs: dict[tuple[str, int, int], list[dict]] = {}
    for row in rows:
        runs.setdefault((row["corner"], row["tx"], row["rx"]), []).append(row)
    points = {key: _point_result(point_runs) for key, point_runs in runs.items()}

    def passing_pairs(at: list[str]) -> list[tuple[int, int]]:
        return [(tx, rx) for tx in tx_codes for rx in rx_codes
                if all((c, tx, rx) in points and points[(c, tx, rx)].passed for c in at)]

    tx_order = _delay_order(meta, tx_codes)
    rx_order = _delay_order(meta, rx_codes)

    def most_margin(pairs, at):
        return _most_margin(pairs, at, points, reset, tx_order, rx_order)

    common = passing_pairs(corners)
    analysis = Analysis(corners=corners, tx=tx_codes, rx=rx_codes, reset=reset, points=points,
                        common=common, recommended=most_margin(common, corners),
                        best_per_corner={}, passing_per_corner={})

    for corner in corners:
        pairs = passing_pairs([corner])
        analysis.passing_per_corner[corner] = len(pairs)
        analysis.best_per_corner[corner] = most_margin(pairs, [corner])

    for variant in meta["variants"]:
        for corner in corners:
            variant_runs = [r for r in rows if r["variant"] == variant and r["corner"] == corner]
            counts = dict.fromkeys(CAUSES, 0)
            for run in variant_runs:
                for cause in row_causes(run):
                    counts[cause] += 1

            passed = sum(run["status"] == "PASS" for run in variant_runs)
            analysis.by_variant[(variant, corner)] = (passed, len(variant_runs), counts)

    return analysis


def _point_result(runs: list[dict]) -> PointResult:
    margins = {key: (min(r[f"{key}_su"] for r in runs), min(r[f"{key}_ho"] for r in runs))
               for key, _ in GROUPS}

    return PointResult(
        passed=all(r["status"] == "PASS" for r in runs),
        worst=min(r["worst"] for r in runs),
        margins=margins,
        causes=set().union(*(row_causes(r) for r in runs)),
        cs_low_max=max(r["cs_low_max"] for r in runs),
    )


def _most_margin(pairs, corners, points, reset, tx_order, rx_order):
    """Largest smallest margin, in 10 ps steps; ties go to the reset pair, then to the
    next margins, then to the pair with more passing neighbours in delay order."""
    if not pairs:
        return None

    candidates = set(pairs)

    def margins_of(pair):
        return sorted(round(min(setup, hold), 2)
                      for corner in corners
                      for setup, hold in points[(corner, *pair)].margins.values())

    def neighbours(pair):
        tx_at, rx_at = tx_order.index(pair[0]), rx_order.index(pair[1])
        near_tx = tx_order[max(tx_at - 1, 0):tx_at + 2]
        near_rx = rx_order[max(rx_at - 1, 0):rx_at + 2]
        return sum((t, r) in candidates for t in near_tx for r in near_rx)

    def score(pair):
        margins = margins_of(pair)
        return margins[0], pair == reset, margins[1:], neighbours(pair)

    return max(pairs, key=score)


def _delay_order(meta: dict, codes: list[int]) -> list[int]:
    # a delay line's delay need not rise with its code
    line = meta["delay_line"]
    typical = line["rise"][line["corners"].index("typ")]

    return sorted(codes, key=lambda code: typical[code])


def verdict(meta: dict, analysis: Analysis) -> dict:
    def pair_summary(pair, corners):
        if pair is None:
            return None

        worst = min(analysis.points[(corner, *pair)].worst for corner in corners)
        return {"tx": pair[0], "rx": pair[1], "worst_slack_ns": round(worst, 3)}

    reset_tx, reset_rx = analysis.reset
    reset_per_corner = {}

    for corner in analysis.corners:
        point = analysis.point(corner, reset_tx, reset_rx)
        if point is None:
            continue

        if point.passed:
            reset_per_corner[corner] = {"pass": True, "worst_slack_ns": round(point.worst, 3)}
        else:
            reset_per_corner[corner] = {"pass": False, "causes": sorted(point.causes)}

    per_corner = {
        corner: {"passing": analysis.passing_per_corner[corner],
                 "best": pair_summary(analysis.best_per_corner[corner], [corner])}
        for corner in analysis.corners
    }

    return {
        "system": meta["system"],
        "pass": bool(analysis.common),
        "points": len(analysis.tx) * len(analysis.rx),
        "points_passing_all_corners": len(analysis.common),
        "recommended": pair_summary(analysis.recommended, analysis.corners),
        "common": [f"{tx}/{rx}" for tx, rx in analysis.common],
        "reset": {
            "tx": reset_tx,
            "rx": reset_rx,
            "pass": bool(reset_per_corner) and all(r["pass"] for r in reset_per_corner.values()),
            "per_corner": reset_per_corner,
        },
        "per_corner": per_corner,
    }
