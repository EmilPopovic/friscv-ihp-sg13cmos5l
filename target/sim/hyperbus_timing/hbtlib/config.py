# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
#
# Matej Jurasić <matej.jurasic@cappig.dev>


"""A system config: one TOML file, every path relative to it and inside the repository."""

from __future__ import annotations

import dataclasses
import os
import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

TOOL_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = TOOL_DIR.parents[2]
CORNERS = ("fast", "typ", "slow")


class ConfigError(Exception):
    pass


@dataclass
class Axi:
    addr: int = 32
    data: int = 32
    id: int = 4
    user: int = 1


@dataclass
class RegBus:
    addr: int = 32
    data: int = 32


@dataclass
class Device:
    part: str = ""
    latency: int = 6
    fixed_latency: bool = True
    program_cr0: bool = True


@dataclass
class Board:
    load_pf: float = 5.0
    flight_ns: float = 0.25
    skew_ns: float = 0.05
    idle: str = "keeper"
    jitter_ns: float = 0.1


@dataclass
class Sweep:
    corners: list[str] = field(default_factory=lambda: list(CORNERS))
    tx: str = "all"
    rx: str = "all"
    n_txn: int = 150
    seed: int = 1
    variants: Any = "auto"
    jobs: int = 0
    timeout_s: int = 900
    startup_cycles: int | None = None


@dataclass
class Check:
    seeds: int = 8
    ocv: float = 0.02
    duty: list[float] = field(default_factory=lambda: [0.5])
    load_pf: list[float] = field(default_factory=lambda: [3.0, 8.0])


@dataclass
class Tools:
    verilator: str = "verilator"
    bender: str = "bender"
    openroad: str = "openroad"
    sta: str = "sta"
    vjobs: int = 0


@dataclass
class Source:
    kind: str  # model, table, char or extract
    file: Path | None = None
    params: dict = field(default_factory=dict)


# per corner [fast, typ, slow], per arc [rise, fall]
MODEL_DEFAULTS = {
    "delay_line": {"step_ns": [0.16, 0.25, 0.40], "offset_ns": [0.05, 0.08, 0.13]},
    "pads": {
        "loads_pf": [2.0, 5.0, 10.0],
        "base_ns": {"out": [1.5, 1.4], "io_out": [1.5, 1.4], "io_in": [0.5, 0.5],
                    "io_en": [1.8, 1.6]},
        "slope_ns_per_pf": {"out": [0.1, 0.07], "io_out": [0.1, 0.07], "io_in": [0.0, 0.0],
                            "io_en": [0.1, 0.07]},
        "corner_scale": [0.7, 1.0, 1.5],
    },
    "chip": {"corner_scale": [0.686, 1.0, 1.58], "typ": {}},
}

GENERATED_BY = {"delay_line": "char", "pads": "char", "chip": "extract"}


@dataclass
class Config:
    path: Path
    name: str
    hyperbus: Path
    bender: Path
    targets: list[str]
    files: list[str]
    clock: str
    period_ns: float
    phys: int
    chips: int
    mem_base: int
    chip_size: int
    reg_base: int
    min_freq_mhz: int
    params: dict
    rst_cfg: dict
    reg_map: dict
    phy_path: str | None
    phy_startup_cycles: int | None
    parts: dict
    flow: dict
    axi: Axi
    reg_bus: RegBus
    device: Device
    board: Board
    sweep: Sweep
    check: Check
    tools: Tools
    delay_line: Source
    pads: Source
    chip: Source

    @property
    def directory(self) -> Path:
        return self.path.parent

    def repo_path(self, value: str | Path) -> Path:
        return inside_repo(self.directory, value)

    def flow_path(self, value: str | Path) -> Path:
        expanded = os.path.expandvars(str(value))
        if "$" in expanded:
            raise ConfigError(f"{value}: environment variable not set (run inside `nix develop`)")

        return inside_repo_or_pdk(self.directory, expanded)


TOP_LEVEL = {
    "name": None, "hyperbus": None, "bender": None,
    "targets": ["rtl", "synthesis"], "files": [],
    "clock": "delayed", "period_ns": 10.0, "phys": 1, "chips": 2,
    "mem_base": 0x8000_0000, "chip_size": 0x0080_0000, "reg_base": 0x1000_0000,
    "min_freq_mhz": 100,
    "params": {}, "rst_cfg": {}, "reg_map": {},
    "phy_path": None, "phy_startup_cycles": None,
    "parts": {}, "flow": {},
}

SECTIONS = {
    "axi": Axi, "reg_bus": RegBus, "board": Board,
    "sweep": Sweep, "check": Check, "tools": Tools,
}


def inside_repo(base: Path, value: str | Path) -> Path:
    path = (base / value).resolve()
    if not path.is_relative_to(REPO_ROOT):
        raise ConfigError(f"{value}: resolves to {path}, outside the repository")

    return path


def pdk_root() -> Path:
    root = os.environ.get("PDK_ROOT")
    if not root:
        raise ConfigError("PDK_ROOT is not set (run inside `nix develop`)")

    return Path(root).resolve()


def inside_repo_or_pdk(base: Path, value: str | Path) -> Path:
    path = (base / value).resolve()
    if not (path.is_relative_to(REPO_ROOT) or path.is_relative_to(pdk_root())):
        raise ConfigError(f"{value}: resolves to {path}, outside the repository and $PDK_ROOT")

    return path


def load(path: str | Path) -> Config:
    path = Path(path).resolve()
    raw = _read_toml(path)

    known = set(TOP_LEVEL) | set(SECTIONS) | {"device"} | set(GENERATED_BY)
    _reject_unknown(raw, known, path.name)

    top = {key: raw.get(key, default) for key, default in TOP_LEVEL.items()}
    if not top["hyperbus"]:
        raise ConfigError(f"{path.name}: hyperbus (the controller's directory) is required")

    base = path.parent
    hyperbus = inside_repo(base, top.pop("hyperbus"))
    bender_dir = top.pop("bender")
    bender = inside_repo(base, bender_dir) if bender_dir else hyperbus

    top["name"] = top["name"] or path.stem
    top["files"] = [f if f.startswith("+") else str(inside_repo(base, f)) for f in top["files"]]

    sections = {key: _section(cls, raw.get(key, {}), key) for key, cls in SECTIONS.items()}
    sources = {name: _source(name, raw.get(name), base) for name in GENERATED_BY}

    cfg = Config(path=path, hyperbus=hyperbus, bender=bender, device=_device(raw.get("device")),
                 **top, **sections, **sources)
    _check(cfg)

    return cfg


def _read_toml(path: Path) -> dict:
    try:
        return tomllib.loads(path.read_text())
    except FileNotFoundError:
        raise ConfigError(f"{path}: no such config") from None
    except tomllib.TOMLDecodeError as err:
        raise ConfigError(f"{path.name}: {err}") from None


def _reject_unknown(raw: dict, known, where: str) -> None:
    unknown = sorted(set(raw) - set(known))
    if unknown:
        raise ConfigError(f"{where}: unknown keys {', '.join(unknown)}")


def _section(cls, raw: dict, where: str):
    _reject_unknown(raw, [f.name for f in dataclasses.fields(cls)], f"[{where}]")
    return cls(**raw)


def _device(raw) -> Device:
    if isinstance(raw, str):
        return Device(part=raw)

    return _section(Device, raw or {}, "device")


def _source(name: str, raw, base: Path) -> Source:
    if raw is None or isinstance(raw, dict):
        overrides = raw or {}
        _reject_unknown(overrides, MODEL_DEFAULTS[name], name)
        return Source("model", params={**MODEL_DEFAULTS[name], **overrides})

    if raw == GENERATED_BY[name]:
        return Source(raw)

    return Source("table", file=inside_repo(base, raw))


def _check(cfg: Config) -> None:
    problems = []

    if cfg.clock not in ("delayed", "divided"):
        problems.append("clock must be delayed or divided")
    if cfg.phys not in (1, 2):
        problems.append("phys must be 1 or 2")
    if cfg.axi.data not in (32, 64):
        problems.append("axi.data must be 32 or 64")
    if cfg.chip_size <= 0 or cfg.chip_size & (cfg.chip_size - 1):
        problems.append("chip_size must be a power of two")
    if cfg.board.idle not in ("keeper", "pulldown", "pullup"):
        problems.append("board.idle must be keeper, pulldown or pullup")
    if not cfg.device.part:
        problems.append("device is required")

    unknown = sorted(set(cfg.sweep.corners) - set(CORNERS))
    if unknown:
        problems.append(f"sweep.corners: unknown corners {', '.join(unknown)}")

    if problems:
        raise ConfigError(f"{cfg.path.name}: " + "; ".join(problems))


def work_dir(cfg: Config, override: str | None = None) -> Path:
    path = Path(override).resolve() if override else TOOL_DIR / "work" / cfg.name
    path.mkdir(parents=True, exist_ok=True)

    return path
