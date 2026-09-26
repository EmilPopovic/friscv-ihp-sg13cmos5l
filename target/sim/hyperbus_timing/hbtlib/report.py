# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
#
# Matej Jurasić <matej.jurasic@cappig.dev>


"""Write a sweep's results to <work>/sweep/<tag>.{txt,verdict.json}."""

from __future__ import annotations

import json
from pathlib import Path

from .analysis import Analysis, analyse, verdict


def write(meta: dict, rows: list[dict], work: Path,
          tag: str = "sweep") -> tuple[Analysis, dict, Path]:
    analysis = analyse(meta, rows)
    summary = verdict(meta, analysis)

    out = Path(work) / "sweep"
    text_path = out / f"{tag}.txt"
    text_path.write_text(text(meta, analysis, summary))
    (out / f"{tag}.verdict.json").write_text(json.dumps(summary, indent=1) + "\n")

    return analysis, summary, text_path


def text(meta: dict, analysis: Analysis, summary: dict) -> str:
    lines = [
        f"{meta['system']}: {meta['device']}, {meta['period_ns']} ns, {meta['clocking']} clocking",
        f"commit {meta.get('commit', 'unknown')}, {meta.get('verilator', 'simulator unknown')}",
        "Cells: worst slack in ns over every check and device variant; # fails.",
    ]

    for corner in analysis.corners:
        lines += tap_map(analysis, corner)

    lines.append("")
    lines.append(f"passing at every corner: {summary['points_passing_all_corners']} "
                 f"of {summary['points']}")

    recommended = summary["recommended"]
    if recommended:
        lines.append(f"recommended: TX {recommended['tx']} / RX {recommended['rx']}, "
                     f"worst slack {recommended['worst_slack_ns']:+.3f} ns")
        lines.append("all passing pairs: " + " ".join(summary["common"]))
    else:
        lines.append("no tap pair passes at every corner")

    cs_low = cs_low_line(meta, analysis)
    if cs_low:
        lines.append(cs_low)

    lines.append("best per corner: " + best_per_corner_line(summary))
    lines.append(reset_line(summary))

    lines += ["", "by device variant:"]
    for variant in meta["variants"]:
        lines.append(f"  {variant}")
        lines += [variant_line(analysis, variant, corner) for corner in analysis.corners]

    return "\n".join(lines) + "\n"


def tap_map(analysis: Analysis, corner: str) -> list[str]:
    lines = ["", f"== {corner} ==", "TX\\RX " + " ".join(f"{rx:>5}" for rx in analysis.rx)]

    for tx in analysis.tx:
        cells = []
        for rx in analysis.rx:
            point = analysis.point(corner, tx, rx)
            cells.append(f"{point.worst:5.2f}" if point and point.passed else "    #")

        lines.append(f"{tx:>5} " + " ".join(cells))

    return lines


def cs_low_line(meta: dict, analysis: Analysis) -> str | None:
    tcsm = meta["device_timing"].get("tcsm_max")
    tx, rx = analysis.recommended or analysis.reset

    points = [analysis.point(corner, tx, rx) for corner in analysis.corners]
    cs_low = [p.cs_low_max for p in points if p is not None]
    if not cs_low or tcsm is None:
        return None

    return f"CS# low max at TX {tx} / RX {rx}: {max(cs_low):.0f} ns (tCSM {tcsm:g} ns)"


def variant_line(analysis: Analysis, variant: str, corner: str) -> str:
    passed, total, counts = analysis.by_variant[(variant, corner)]
    line = f"    {corner:<4} {passed:4}/{total} pass"

    failing = [f"{cause} {n}" for cause, n in counts.items() if n]
    if failing:
        line += "; failing: " + ", ".join(failing)

    return line


def reset_line(summary: dict) -> str:
    reset = summary["reset"]
    parts = []

    for corner, result in reset["per_corner"].items():
        if result["pass"]:
            parts.append(f"{corner} pass {result['worst_slack_ns']:+.3f} ns")
        else:
            parts.append(f"{corner} FAIL ({', '.join(result['causes'])})")

    return f"reset taps TX {reset['tx']} / RX {reset['rx']}: " + ", ".join(parts)


def best_per_corner_line(summary: dict) -> str:
    parts = []

    for corner, result in summary["per_corner"].items():
        best = result["best"]
        if best:
            parts.append(f"{corner} TX {best['tx']} / RX {best['rx']} "
                         f"({result['passing']} passing)")
        else:
            parts.append(f"{corner} none")

    return "; ".join(parts)
