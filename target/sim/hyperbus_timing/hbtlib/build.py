# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
#
# Matej Jurasić <matej.jurasic@cappig.dev>


"""Build the testbench with Verilator."""

from __future__ import annotations

import subprocess
from pathlib import Path

from . import testbench, timing
from .config import Config
from .rtl import Controller

NOT_FOUND = "not found (run inside `nix develop`)"


class BuildError(Exception):
    pass


def build(cfg: Config, ctl: Controller, work: Path, *, fast: bool = False,
          min_period_ns: float | None = None, force: bool = False, log=print) -> Path:
    """A fast build starts the PHY just past tVCS, at clock periods down to min_period_ns."""
    gen = testbench.generate(cfg, ctl, work)
    obj = Path(work) / _object_dir(fast, min_period_ns)
    binary = obj / "hbt_sim"
    file_list = gen / "sources.f"

    defines = ["+define+ASSERTS_OFF"]
    if fast:
        device = timing.device_parts(cfg)[cfg.device.part]
        cycles = testbench.sweep_startup_cycles(cfg, device, min_period_ns)
        defines.append(f"+define+HBT_STARTUP_CYCLES={cycles}")

    stamp = obj / "built_with.txt"
    built_with = "\n".join([verilator_version(cfg), *defines]) + "\n"
    if not force and _up_to_date(binary, stamp, built_with, file_list):
        log(f"up to date: {binary}")
        return binary

    obj.mkdir(parents=True, exist_ok=True)
    command = [
        cfg.tools.verilator, "--binary", "--timing", "-j", str(cfg.tools.vjobs),
        "--top-module", "hbt_tb", "-Wno-fatal", "-Wno-lint", "-Wno-style",
        "--timescale", "1ns/1ps", "-O2", "--x-assign", "unique", "--x-initial", "unique",
        # Verilator 5.046 splits the traffic coroutine across its fork otherwise
        "--output-split-cfuncs", "0",
        *defines, f"-I{gen}", f"-I{testbench.TB_DIR}",
        "--Mdir", str(obj), "-f", str(file_list), "-o", "hbt_sim",
    ]

    build_log = obj / "build.log"
    log(f"building {binary}")

    try:
        with open(build_log, "w") as out:
            result = subprocess.run(command, stdout=out, stderr=subprocess.STDOUT)
    except FileNotFoundError:
        raise BuildError(f"{cfg.tools.verilator} {NOT_FOUND}") from None

    if result.returncode or not binary.exists():
        errors = [line for line in build_log.read_text().splitlines() if "%Error" in line]
        raise BuildError("Verilator failed:\n  " + "\n  ".join(errors[:12] or [f"see {build_log}"]))

    stamp.write_text(built_with)
    return binary


def verilator_version(cfg: Config) -> str:
    try:
        result = subprocess.run([cfg.tools.verilator, "--version"], capture_output=True, text=True)
    except FileNotFoundError:
        raise BuildError(f"{cfg.tools.verilator} {NOT_FOUND}") from None

    return result.stdout.strip()


def _object_dir(fast: bool, min_period_ns: float | None) -> str:
    if not fast:
        return "obj"
    if min_period_ns is None:
        return "obj_fast"

    return f"obj_fast_{min_period_ns:g}ns"


def _up_to_date(binary: Path, stamp: Path, built_with: str, file_list: Path) -> bool:
    if not binary.exists() or not stamp.exists() or stamp.read_text() != built_with:
        return False

    built = binary.stat().st_mtime
    return all(not p.exists() or p.stat().st_mtime < built for p in _inputs(file_list))


def _inputs(file_list: Path) -> list[Path]:
    inputs = [file_list]

    for line in file_list.read_text().splitlines():
        if line.startswith("+incdir+"):
            inputs += Path(line.removeprefix("+incdir+")).glob("*.svh")
        elif not line.startswith("+"):
            inputs.append(Path(line))

    return inputs
