#!/usr/bin/env python3
# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
#
# Emil Popovic <mail@emilpopovic.me>

# Post-PnR max slew check. Accepts pad violations.
# Usage: check_slew.py [run directory, default latest]

import pathlib
import re
import sys

STA_STEP_GLOB = "*-openroad-stapostpnr"


def red(s) -> str:    return f"\033[91m{s}\033[00m"
def green(s) -> str:  return f"\033[92m{s}\033[00m"
def yellow(s) -> str: return f"\033[93m{s}\033[00m"


def newest_run(base: pathlib.Path) -> pathlib.Path:
    runs = sorted(base.glob("RUN_*"))
    if not runs:
        print(red("CHECK SLEW FAILED"))
        sys.exit(f"no runs under {base}")
    return runs[-1]


def violators(checks_rpt: pathlib.Path):
    # Yield (pin, limit, slew) from the max slew section
    lines = checks_rpt.read_text().splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == "max slew")
    except StopIteration:
        return
    for line in lines[start + 1:]:
        if line.strip() in ("max capacitance", "max fanout") or line.startswith("max slew violation count"):
            break
        if "(VIOLATED)" not in line:
            continue
        fields = line.split()
        yield fields[0], float(fields[1]), float(fields[2])


def pad_signal(pin: str):
    # Map a pad node to its signal
    m = re.fullmatch(r"(?:IO_BOND_)?(.+)_pad/pad", pin)
    if m:
        name = re.sub(r"_pads\[(\d+)\]\.\w+$", r"[\1]", m.group(1))
        return name
    m = re.fullmatch(r"([A-Za-z0-9_]+)_PAD(\[\d+\])?", pin)
    if m:
        return m.group(1) + (m.group(2) or "")
    return None


def main() -> int:
    here = pathlib.Path(__file__).resolve().parent.parent
    run = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else newest_run(here / "librelane" / "runs")

    sta_steps = sorted(run.glob(STA_STEP_GLOB))
    if not sta_steps:
        print(red("CHECK SLEW FAILED"))
        sys.exit(f"{run}: no {STA_STEP_GLOB} step, did the flow reach post-PnR STA?")
    corners = sorted(p for p in sta_steps[-1].iterdir() if (p / "checks.rpt").is_file())

    print(f"run: {run.name}\n")
    pads: dict[str, dict[str, float]] = {}
    offenders: list[tuple[str, float, float, str]] = []
    for corner in corners:
        n_pad = n_other = 0
        for pin, limit, slew in violators(corner / "checks.rpt"):
            signal = pad_signal(pin)
            if signal is None:
                # This violator is not a pad, report it as an offender
                offenders.append((pin, limit, slew, corner.name))
                n_other += 1
            else:
                # This violator is a pad, not an offender, just report it
                worst = pads.setdefault(signal, {})
                worst[corner.name] = max(slew, worst.get(corner.name, 0.0))
                n_pad += 1
        print(f"  {corner.name:24s} pad {n_pad:3d}   other {n_other:3d}")

    if pads:
        names = [c.name for c in corners]
        print(f"\n{yellow('NOTE')} {len(pads)} pad signals over the limit (accepted), worst slew per corner [ns]:")
        print("  " + " " * 20 + "".join(f"{n.split('_')[1]:>9s}" for n in names))
        for signal, worst in sorted(pads.items(), key=lambda kv: -max(kv[1].values())):
            print(f"  {signal:20s}" + "".join(f"{worst[n]:9.3f}" if n in worst else f"{'-':>9s}" for n in names))

    if not offenders:
        print(f"\n{green('PASS')}")
        return 0

    print(f"\n{red('FAIL')} {len(offenders)} non-pad max slew violation(s)\n")
    for pin, limit, slew, corner in sorted(offenders, key=lambda o: o[1] - o[2]):
        print(f"  {slew:6.3f} ns vs {limit:.4f} ns limit   ({corner})  {pin}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
