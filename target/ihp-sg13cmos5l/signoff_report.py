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
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
RUNS = HERE / "librelane" / "runs"

# metric -> label
BLOCKING = [
    ("design__lvs_error__count", "LVS errors"),
    ("design__lvs_unmatched_net__count", "LVS unmatched nets"),
    ("design__lvs_unmatched_device__count", "LVS unmatched devices"),
    ("design__lvs_unmatched_pin__count", "LVS unmatched pins"),
    ("klayout__drc_error__count", "KLayout DRC"),
    ("route__drc_errors", "routing DRC"),
    ("design__xor_difference__count", "GDS XOR differences"),
    ("klayout__density_error__count", "metal density"),
    ("antenna__violating__nets", "antenna nets"),
    ("design__disconnected_pin__count", "disconnected pins"),
    ("design__critical_disconnected_pin__count", "critical disconnected pins"),
    ("design__power_grid_violation__count", "power grid violations"),
    ("design__max_cap_violation__count", "max capacitance"),
    ("timing__setup_vio__count", "setup violations"),
    ("timing__hold_vio__count", "hold violations"),
]

CORNERS = ["nom_fast_1p32V_m40C", "nom_typ_1p20V_25C", "nom_slow_1p08V_125C"]


def red(s) -> str:          return f"\033[91m{s}\033[00m"
def green(s) -> str:        return f"\033[92m{s}\033[00m"
def yellow(s) -> str:       return f"\033[93m{s}\033[00m"
def light_purple(s) -> str: return f"\033[94m{s}\033[00m"
def purple(s) -> str:       return f"\033[95m{s}\033[00m"
def cyan(s) -> str:         return f"\033[96m{s}\033[00m"
def light_gray(s) -> str:   return f"\033[97m{s}\033[00m"
def black(s) -> str:        return f"\033[90m{s}\033[00m"
def conditional_ge0(s) -> str:
    return f"{green(s) if float(s) >= 0 else red(s)}"


def load_metrics(run: pathlib.Path) -> dict | None:
    for candidate in ("final/metrics.json",):
        p = run / candidate
        if p.is_file():
            return json.loads(p.read_text())
    sta = sorted(run.glob("*-openroad-stapostpnr/state_out.json"))
    if sta:
        return json.loads(sta[-1].read_text()).get("metrics", {})
    return None


def flow_completed(run: pathlib.Path) -> tuple[bool, str]:
    if (run / "final" / "metrics.json").is_file():
        return True, "complete, final views written"
    steps = sorted(p.name for p in run.iterdir() if p.is_dir() and p.name[0].isdigit())
    return False, f"incomplete, last step: {steps[-1] if steps else '(none)'}"


def report(run: pathlib.Path) -> bool:
    print(yellow(run.name))
    print()
    done, how = flow_completed(run)
    metrics = load_metrics(run)

    if metrics is None:
        print(f"  {cyan('FLOW RESULT')}: {how}")
        return False
    print(f"  {cyan('FLOW RESULT')}: {how}")

    print(cyan("\n  BLOCKING"))
    blocking_bad = []
    for key, label in BLOCKING:
        value = metrics.get(key)
        if value is None:
            print(f"    {'?':>8}  {label:<30}  {yellow('NOT REPORTED')}")
            if done:
                blocking_bad.append(f"{label}: not reported")
            continue
        ok = float(value) == 0
        print(f"    {str(value):>8}  {label:<30}  {green('PASS') if ok else red('FAIL')}")
        if not ok:
            blocking_bad.append(f"{label}={value}")

    print(f"\n  {cyan('MARGIN')} (worst slack, ns)")
    margins = {}
    for kind in ("setup", "hold"):
        row = []
        for c in CORNERS:
            v = metrics.get(f"timing__{kind}__ws__corner:{c}")
            row.append(f"{c.split('_')[1]:>5}={conditional_ge0(f'{float(v):+.4f}')}" if v is not None else f"{c}={red('?')}")
            if v is not None:
                margins[(kind, c)] = float(v)
        print(f"    {kind:5s}  " + "   ".join(row))
    worst_hold = min((v for (k, _), v in margins.items() if k == "hold"), default=None)
    worst_setup = min((v for (k, _), v in margins.items() if k == "setup"), default=None)

    ir = metrics.get("design_powergrid__drop__worst")
    if ir is not None:
        print(f"\n  {cyan('IR DROP')} (worst): {float(ir) * 1000:.2f} mV")

    print(f"\n  {cyan('ADVISORY')}")
    slew = subprocess.run(
        [sys.executable, str(HERE / "check_slew.py"), str(run)],
        capture_output=True, text=True,
    )
    slew_ok = slew.returncode == 0
    for line in slew.stdout.splitlines():
        if line.strip() and not line.startswith("run:"):
            print(f"    {line}")
    if not slew_ok:
        blocking_bad.append("macro slew vendor rule")

    verdict_pass: bool = True if (
        done
        and not blocking_bad
        and worst_hold and worst_hold > 0
        and worst_setup and worst_setup > 0
    ) else False
    print(f"\n  {cyan('VERDICT')}: {green('PASS') if verdict_pass else red('FAIL')}")
    if blocking_bad:
        print(red("    blocking: " + "; ".join(blocking_bad)))
    if verdict_pass:
        print(f"    worst margin: hold {conditional_ge0(f'{worst_hold:+.4f}') } ns, setup {conditional_ge0(f'{worst_setup:+.4f}') } ns")
    return verdict_pass


def main() -> int:
    args = sys.argv[1:]
    runs = [pathlib.Path(a) for a in args] if args else [sorted(RUNS.glob("*"))[-1]]
    verdicts = {}
    for r in runs:
        if not r.is_dir():
            print(f"skip {r}: not a directory")
            continue
        verdicts[r.name] = report(r)
    print()
    print(yellow('SUMMARY'))
    for name, v in verdicts.items():
        print(f"   {green('PASS') if v else red('FAIL')} {name}")
    return 0 if all(verdicts.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
