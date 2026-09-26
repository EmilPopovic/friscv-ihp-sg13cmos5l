# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
#
# Matej Jurasić <matej.jurasic@cappig.dev>


"""Settings for `hbt char` and `hbt extract`, and running their Tcl scripts.

pdks/<pdk>.toml, then the LibreLane run's resolved.json, then [flow], each overriding
the one before.
"""

from __future__ import annotations

import fnmatch
import json
import os
import re
import subprocess
import tomllib
from pathlib import Path

from .config import CORNERS, REPO_ROOT, TOOL_DIR, Config, ConfigError, pdk_root

FILE_KEYS = ("macro", "odb", "guide")


class FlowSettings(dict):
    def __missing__(self, key):
        raise ConfigError(f"[flow] needs {key}, or a LibreLane run whose resolved.json has it")


def resolve(cfg: Config, run: str | None = None, odb: str | None = None) -> FlowSettings:
    settings = dict(cfg.flow)

    if settings.get("pdk"):
        profile = TOOL_DIR / "pdks" / f"{settings['pdk']}.toml"
        if not profile.exists():
            raise ConfigError(f"no PDK profile {profile}")
        settings = {**tomllib.loads(profile.read_text()), **settings}

    if run:
        settings["run"] = Path(run).resolve()
    if odb:
        settings["odb"] = Path(odb).resolve()

    _locate(cfg, settings)

    if settings.get("run"):
        run_dir = cfg.repo_path(settings["run"])
        settings["run"] = str(run_dir)
        _add_run_settings(settings, run_dir)
        _locate(cfg, settings)

    return FlowSettings(settings)


def _locate(cfg: Config, settings: dict) -> None:
    def locate(path) -> str:
        return str(cfg.flow_path(path))

    for key in FILE_KEYS:
        if settings.get(key):
            settings[key] = locate(settings[key])

    if "libs" in settings:
        settings["libs"] = {c: [locate(f) for f in files] for c, files in settings["libs"].items()}
    if "lefs" in settings:
        settings["lefs"] = [locate(f) for f in settings["lefs"]]
    if "spef" in settings:
        settings["spef"] = {c: locate(f) for c, f in settings["spef"].items()}


def _add_run_settings(settings: dict, run: Path) -> None:
    resolved = run / "resolved.json"
    if not resolved.exists():
        raise ConfigError(f"{resolved} not found: [flow] run must be a LibreLane run directory")

    flow = _moved_here(json.loads(resolved.read_text()), run)
    names = settings.get("corners") or {}
    if set(names) != set(CORNERS):
        raise ConfigError("[flow] corners must name the run's fast, typ and slow STA corners")

    macros = flow.get("MACROS") or {}

    def libs_at(corner: str) -> list[str]:
        libs = list(flow["LIB"][names[corner]])
        for macro in macros.values():
            libs += _for_corner(macro.get("lib"), names[corner]) or []
        return libs

    if "libs" not in settings:
        settings["libs"] = {corner: libs_at(corner) for corner in CORNERS}
    if "lefs" not in settings:
        settings["lefs"] = [_for_corner(flow.get("TECH_LEFS"), names["typ"]),
                            *(flow.get("CELL_LEFS") or [])]
    if "layer_rc" not in settings:
        layer_rc = _for_corner(flow.get("LAYERS_RC"), names["typ"]) or {}
        settings["layer_rc"] = [[layer, rc["res"], rc["cap"]] for layer, rc in layer_rc.items()]

    if flow.get("CLOCK_PORT"):
        settings.setdefault("clock_port", flow["CLOCK_PORT"])
    if flow.get("CLOCK_NET"):
        settings.setdefault("clock_root", flow["CLOCK_NET"])

    if "macro" not in settings:
        for macro in macros.values():
            if any("i_delay_" in instance for instance in macro.get("instances", {})):
                lib = _for_corner(macro["lib"], names["typ"])[0]
                settings["macro"] = str(Path(lib).with_suffix(""))
                break

    if "odb" not in settings:
        databases = sorted(run.glob("*/*.odb"), key=lambda p: _step_number(p.parent))
        if not databases:
            raise ConfigError(f"no */*.odb under {run}")
        settings["odb"] = str(databases[-1])

    if "spef" not in settings:
        settings["spef"] = _spef_files(run, Path(settings["odb"]), names)


def _moved_here(flow: dict, run: Path) -> dict:
    """resolved.json with the recorded checkout and PDK paths moved to this machine's."""
    design_dir = run.parent.parent
    moves = []

    if flow.get("PDK_ROOT"):
        moves.append((flow["PDK_ROOT"].rstrip("/"), str(pdk_root())))

    recorded = (flow.get("DESIGN_DIR") or "").rstrip("/")
    if recorded and design_dir.is_relative_to(REPO_ROOT):
        inside = "/" + design_dir.relative_to(REPO_ROOT).as_posix()
        if recorded.endswith(inside):
            moves.append((recorded.removesuffix(inside), str(REPO_ROOT)))

    def move(value):
        if isinstance(value, dict):
            return {key: move(item) for key, item in value.items()}
        if isinstance(value, list):
            return [move(item) for item in value]

        if isinstance(value, str):
            for old, new in moves:
                if value == old or value.startswith(old + "/"):
                    return new + value[len(old):]

        return value

    return move(flow)


def _spef_files(run: Path, odb: Path, names: dict) -> dict[str, str]:
    # RCX writes a directory per corner, or per RC set ("nom" for "nom_fast_...")
    routing_steps = [_step_number(p) for p in run.glob("*detailedrouting*")]
    odb_step = _step_number(odb.parent) if odb.parent.parent == run else -1
    if not routing_steps or odb_step < min(routing_steps):
        return {}

    candidates = [*run.glob("*/*/*.spef"), *run.glob("*/*/*/*.spef")]

    def step_of(spef: Path) -> int:
        return _step_number(run / spef.relative_to(run).parts[0])

    spefs = {}
    for corner in CORNERS:
        name = names[corner]
        found = [s for s in candidates
                 if name == s.parent.name or name.startswith(s.parent.name + "_")]
        if found:
            spefs[corner] = str(max(found, key=step_of))

    return spefs


def _step_number(step_dir: Path) -> int:
    match = re.match(r"(\d+)-", step_dir.name)
    return int(match.group(1)) if match else 1 << 30


def _for_corner(per_corner: dict | None, corner: str):
    for pattern, value in (per_corner or {}).items():
        if fnmatch.fnmatch(corner, pattern):
            return value

    return None


def write_params(path: Path, params: dict) -> None:
    def quote(value) -> str:
        return "{" + str(value) + "}"

    lines = []
    for name, value in params.items():
        if isinstance(value, (list, tuple)):
            value = " ".join(quote(v) for v in value)
        lines.append(f"set {name} {quote(value)}")

    Path(path).write_text("\n".join(lines) + "\n")


def run_tcl(tool: str, script: str, params_file: Path) -> None:
    """Run tcl/<script>, which reads its parameters from $PARAMS."""
    params_file = Path(params_file)
    log = params_file.with_suffix(".log")
    command = [tool, "-no_init", "-exit", str(TOOL_DIR / "tcl" / script)]

    try:
        with open(log, "w") as out:
            result = subprocess.run(command, stdout=out, stderr=subprocess.STDOUT,
                                    cwd=params_file.parent,
                                    env={**os.environ, "PARAMS": str(params_file)})
    except FileNotFoundError:
        raise ConfigError(f"{tool} not found (run inside `nix develop`)") from None

    if result.returncode:
        raise ConfigError(f"{tool} {script} failed, see {log}")
