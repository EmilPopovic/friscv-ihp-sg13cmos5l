#!/usr/bin/env python3
# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
#
# Emil Popović <mail@emilpopovic.me>

import json
import pathlib
import re
import sys

STA_STEP_GLOB = "*-openroad-stapostpnr"


def red(s) -> str:          return f"\033[91m{s}\033[00m"
def green(s) -> str:        return f"\033[92m{s}\033[00m"
def yellow(s) -> str:       return f"\033[93m{s}\033[00m"
def light_purple(s) -> str: return f"\033[94m{s}\033[00m"
def purple(s) -> str:       return f"\033[95m{s}\033[00m"
def cyan(s) -> str:         return f"\033[96m{s}\033[00m"
def light_gray(s) -> str:   return f"\033[97m{s}\033[00m"
def black(s) -> str:        return f"\033[90m{s}\033[00m"


def newest_run(base: pathlib.Path) -> pathlib.Path:
    runs = sorted(base.glob("RUN_*"))
    if not runs:
        print(red("CHECK SLEW FAILED"))
        sys.exit(f"no runs under {base}")
    return runs[-1]


def max_transition_constraint(run: pathlib.Path) -> float:
    resolved = run / "resolved.json"
    if resolved.is_file():
        value = json.loads(resolved.read_text()).get("MAX_TRANSITION_CONSTRAINT")
        if value is not None:
            return float(value)
    print(red("CHECK SLEW FAILED"))
    sys.exit(f"{resolved}: MAX_TRANSITION_CONSTRAINT not found")


def vendor_slew_rule(run: pathlib.Path) -> tuple[float, list[str]]:
    # Get default_max_transition from all macro liberty files, return the smallest
    resolved = json.loads((run / "resolved.json").read_text())
    libs: list[pathlib.Path] = []
    for macro in (resolved.get("MACROS") or {}).values():
        for paths in (macro.get("lib") or {}).values():
            libs.extend(pathlib.Path(x) for x in paths)
    rule, seen = None, []
    for lib in sorted(set(libs)):
        if not lib.is_file():
            continue
        m = re.search(r"default_max_transition\s*:\s*([0-9.]+)", lib.read_text())
        if not m:
            continue
        value = float(m.group(1))
        seen.append(f"{lib.name}: {value}")
        rule = value if rule is None else min(rule, value)
    if rule is None:
        print(red("CHECK SLEW FAILED"))
        sys.exit("no macro liberty declared default_max_transition")
    return rule, seen


def violators(checks_rpt: pathlib.Path):
    # Yield (pin, limit, slew) from the max slew section
    lines = checks_rpt.read_text().splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == "max slew")
        end = next(i for i, l in enumerate(lines) if i > start and l.strip() == "max fanout")
    except StopIteration:
        sys.exit(f"{checks_rpt}: could not locate max slew section")
    for line in lines[start:end]:
        if "(VIOLATED)" not in line:
            continue
        fields = line.split()
        yield fields[0], float(fields[1]), float(fields[2])


def is_pad(pin: str) -> bool:
    return bool(
        re.search(r"(^|\.)IO_BOND_", pin)
        or re.search(r"_pad/", pin)
        or re.match(r"^[A-Za-z0-9_]+_PAD(\[\d+\])?$", pin)
    )


def main() -> int:
    here = pathlib.Path(__file__).resolve().parent
    run = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else newest_run(here / "librelane" / "runs")
    limit_dr = max_transition_constraint(run)

    sta_steps = sorted(run.glob(STA_STEP_GLOB))
    if not sta_steps:
        print(red("CHECK SLEW FAILED"))
        sys.exit(f"{run}: no {STA_STEP_GLOB} step, did the flow reach post-PnR STA?")
    sta = sta_steps[-1]

    rule, seen = vendor_slew_rule(run)
    print(f"run: {run.name}")
    print(f"  design-rule max transition: {limit_dr} ns")
    print(f"  macro vendor rule (default_max_transition): {rule} ns")
    for line in seen:
        print(f"      {line}")
    print()
    offenders: dict[str, tuple[float, float, str]] = {}
    extrapolating: dict[str, tuple[float, float, str]] = {}
    for corner_dir in sorted(p for p in sta.iterdir() if (p / "checks.rpt").is_file()):
        lib, dr_core, dr_pad = [], [], []
        for pin, limit, slew in violators(corner_dir / "checks.rpt"):
            if limit < limit_dr:
                lib.append((pin, limit, slew))
                bucket = offenders if slew > rule else extrapolating
                prev = bucket.get(pin)
                if prev is None or slew > prev[1]:
                    bucket[pin] = (limit, slew, corner_dir.name)
            elif is_pad(pin):
                dr_pad.append((pin, limit, slew))
            else:
                dr_core.append((pin, limit, slew))
        print(
            f"  {corner_dir.name:24s} library-limit {len(lib):3d}   design-rule core {len(dr_core):3d}   design-rule pad {len(dr_pad):3d}"
        )

    if extrapolating:
        print(f"\n{yellow('NOTE')}: {len(extrapolating)} pin(s) past the characterised slew axis but are within the {rule} ns vender rule")
        for pin, (limit, slew, corner) in sorted(extrapolating.items(), key=lambda kv: -kv[1][1]):
            over = 100.0 * (slew - limit) / limit
            print(f"  {slew:6.3f} ns vs {limit:.4f} top ({over:.1f}% over)  ({corner})  {pin}")

    if not offenders:
        print(f"\n{green('PASS')}: no pin exceeds vendor rule")
        return 0

    print(f"\n{red('FAIL')}: {len(offenders)} pin(s) exceed vendor rule")
    print("      Violations:\n")
    for pin, (limit, slew, corner) in sorted(offenders.items(), key=lambda kv: -kv[1][1]):
        print(f"  {slew:6.3f} ns vs {rule} ns rule   ({corner})  {pin}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
