# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
#
# Matej Jurasić <matej.jurasic@cappig.dev>


"""Read parameters, ports, registers, reset values and PHY paths from a PULP hyperbus tree."""

from __future__ import annotations

import math
import re
from dataclasses import dataclass, field
from pathlib import Path

from .config import REPO_ROOT

REQUIRED_REGISTERS = ("t_latency_access", "en_latency_additional", "t_burst_max",
                      "t_rx_clk_delay", "t_tx_clk_delay", "address_space")
CLOCK_PARAMS = ("IsClockODelayed", "UsePhyClkDivider")
MODULE_HEADER = r"\bmodule\s+{}\b(?:\s+import\s+[\w:*,\s]+;)?"
PAREN_DEPTH = {"(": 1, ")": -1}


class RtlError(Exception):
    pass


@dataclass
class Controller:
    root: Path
    params: list[str] = field(default_factory=list)
    ports: list[str] = field(default_factory=list)
    clock_param: str = ""
    registers: dict[str, int] = field(default_factory=dict)
    reset: dict[str, int] = field(default_factory=dict)
    cfg_fields: list[str] = field(default_factory=list)
    states: list[str] = field(default_factory=list)
    code_width: int = 4
    num_codes: int = 16
    delay_ports: list[str] = field(default_factory=list)
    startup_default: int = 60000
    cs_clock: str = "tx90"  # or core_fall
    phy_path_1: str = ""
    phy_path_2: str = ""    # {p} is the PHY index

    def phy_path(self, num_phys: int) -> str:
        return self.phy_path_2 if num_phys == 2 else self.phy_path_1

    def reset_codes(self, rst_cfg: dict) -> tuple[int, int]:
        values = {**self.reset, **rst_cfg}
        tx = values.get("t_tx_clk_delay", 0) % self.num_codes
        rx = values.get("t_rx_clk_delay", 0) % self.num_codes

        return tx, rx

    def clock_param_value(self, clock: str) -> int:
        delayed = clock == "delayed"
        return int(delayed if self.clock_param == "IsClockODelayed" else not delayed)

    def summary(self) -> str:
        cs = "the falling core clock" if self.cs_clock == "core_fall" else "the TX 90-degree clock"
        root = self.root
        if root.is_relative_to(REPO_ROOT):
            root = root.relative_to(REPO_ROOT)

        return (f"hyperbus at {root}: {self.clock_param}, {self.num_codes} taps "
                f"({self.code_width}-bit registers), "
                f"reset codes TX {self.reset.get('t_tx_clk_delay')} "
                f"RX {self.reset.get('t_rx_clk_delay')}, CS# on {cs}, PHY {self.phy_path_1}")


def detect(root: str | Path) -> Controller:
    root = Path(root).resolve()
    ctl = Controller(root=root)

    phy_if = _parse_top(ctl, _source(root, "hyperbus.sv"))
    _parse_package(ctl, _source(root, "hyperbus_pkg.sv"))
    _parse_registers(ctl, _source(root, "hyperbus_cfg_regs.sv"))
    _parse_delay(ctl, _source(root, "hyperbus_delay.sv"))
    _parse_cs_clock(ctl, _source(root, "hyperbus_trx.sv"))
    _parse_phy_paths(ctl, _source(root, "hyperbus_phy_if.sv"), phy_if)

    return ctl


def _source(root: Path, name: str) -> str:
    path = root / "src" / name
    if not path.exists():
        raise RtlError(f"{path} not found; `hyperbus` must point at the hyperbus IP root")

    text = re.sub(r"/\*.*?\*/", " ", path.read_text(), flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def _parse_top(ctl: Controller, text: str) -> str:
    header = re.search(MODULE_HEADER.format("hyperbus") + r"\s*#\s*\(", text)
    if not header:
        raise RtlError("module hyperbus with parameters not found")

    params_end = _closing_paren(text, header.end())
    params = text[header.end():params_end - 1]
    ctl.params = re.findall(r"parameter\s+(?:[\w:]+\s+|\[[^\]]*\]\s*)*?(\w+)\s*=", params)

    clock_params = [p for p in CLOCK_PARAMS if p in ctl.params]
    if not clock_params:
        raise RtlError("hyperbus has neither IsClockODelayed nor UsePhyClkDivider")
    ctl.clock_param = clock_params[0]

    ports_start = text.index("(", params_end)
    ports = text[ports_start + 1:text.index(");", ports_start)]
    ports = re.sub(r"`ifdef\b.*?`endif", "", ports, flags=re.S)
    ports = re.sub(r"`(ifndef|else|endif)[^\n]*", "", ports)
    ctl.ports = re.findall(r"\b(?:input|output|inout)\b[^,]*?(\w+)\s*(?=,|$)", ports, re.S)

    startup = re.search(r"PhyStartupCycles\s*=\s*([\d\s*]+)", params)
    if startup:
        ctl.startup_default = math.prod(int(f) for f in startup.group(1).split("*"))

    phy_if = re.search(r"\bhyperbus_phy_if\s*#\s*\(.*?\)\s*(\w+)\s*\(", text, re.S)
    return phy_if.group(1) if phy_if else "i_phy"


def _parse_package(ctl: Controller, text: str) -> None:
    width = re.search(r"logic\s*\[(\d+)\s*:\s*0\]\s*t_tx_clk_delay\s*;", text)
    if width:
        ctl.code_width = int(width.group(1)) + 1

    cfg = re.search(r"typedef\s+struct\s+packed\s*\{([^}]*)\}\s*hyper_cfg_t", text)
    if cfg:
        ctl.cfg_fields = re.findall(r"(\w+)\s*;", cfg.group(1))

    states = re.search(r"typedef\s+enum\s+logic\s*\[[^\]]*\]\s*\{([^}]*)\}\s*hyper_phy_state_t",
                       text)
    if not states:
        raise RtlError("hyper_phy_state_t not found in hyperbus_pkg.sv")
    ctl.states = [s.strip() for s in states.group(1).split(",") if s.strip()]

    reset = re.search(r"function\s+automatic\s+hyper_cfg_t\s+gen_RstCfg.*?endfunction", text, re.S)
    if reset:
        for name, value in re.findall(r"(\w+)\s*:\s*(\d*'[hdbo][0-9a-fA-F_]+|\d+)\s*,",
                                      reset.group(0)):
            ctl.reset[name] = _sv_int(value)


def _parse_registers(ctl: Controller, text: str) -> None:
    for index, name in re.findall(r"'h([0-9a-fA-F]+)\s*:\s*cfg_d\.(\w+)", text):
        ctl.registers[name] = int(index, 16)

    missing = [r for r in REQUIRED_REGISTERS if r not in ctl.registers]
    if missing:
        raise RtlError(f"registers {', '.join(missing)} not found in hyperbus_cfg_regs.sv")


def _parse_delay(ctl: Controller, text: str) -> None:
    instance = re.search(r"\bconfigurable_delay\s*#\s*\(\s*\.NUM_STEPS\s*\(\s*(\d+)\s*\)\s*\)"
                         r"\s*\w+\s*\((.*?)\)\s*;", text, re.S)
    if not instance:
        raise RtlError("configurable_delay instance not found in hyperbus_delay.sv")

    ctl.num_codes = int(instance.group(1))
    ctl.delay_ports = re.findall(r"\.(\w+)\s*\(", instance.group(2))


def _parse_cs_clock(ctl: Controller, text: str) -> None:
    known = {("negedge", "clk_i"): "core_fall", ("posedge", "tx_clk_90"): "tx90"}

    for block in re.finditer(r"always_ff\s*@\s*\(\s*(posedge|negedge)\s+(\w+)", text):
        body = text[block.end():text.find("always_ff", block.end())]
        if not re.search(r"hyper_cs_no\s*<=", body):
            continue

        if block.groups() not in known:
            raise RtlError(f"CS# flop on {' '.join(block.groups())}: unknown hyperbus version")

        ctl.cs_clock = known[block.groups()]
        return


def _parse_phy_paths(ctl: Controller, text: str, phy_if: str) -> None:
    for construct in generate_constructs(_module_body(text, "hyperbus_phy_if")):
        if construct.kind != "if" or not construct.text.startswith("if ( NumPhys == 2 )"):
            continue

        phys = re.findall(r"\bhyperbus_phy\s*#\s*\(.*?\)\s*(\w+)\s*\(", construct.text, re.S)
        loop = re.search(r"\bfor\s*\(.*?\)\s*begin\s*:\s*(\w+)", construct.text, re.S)
        if len(phys) < 2 or not loop or not construct.label:
            raise RtlError("unexpected generate structure around hyperbus_phy "
                           "in hyperbus_phy_if.sv")

        else_block = construct.else_label or f"genblk{construct.number}"
        ctl.phy_path_2 = f"{phy_if}.{construct.label}.{loop.group(1)}[{{p}}].{phys[0]}"
        ctl.phy_path_1 = f"{phy_if}.{else_block}.{phys[-1]}"
        return

    raise RtlError("NumPhys generate block not found in hyperbus_phy_if.sv")


@dataclass
class GenerateConstruct:
    number: int
    kind: str
    label: str | None
    else_label: str | None
    text: str


def generate_constructs(body: str) -> list[GenerateConstruct]:
    # unnamed construct n is genblk<n> (IEEE 1800 27.6), counting the named ones too
    tokens = re.findall(r"[A-Za-z_]\w*|\d+|==|!=|<=|>=|::|\S", body)
    scan = _TokenScanner(tokens)
    found = []
    number = 0
    i = 0

    while i < len(tokens):
        token = tokens[i]

        if token in ("function", "task", "class"):
            i = tokens.index("end" + token, i) + 1
        elif token in ("always", "always_ff", "always_comb", "always_latch", "initial", "final"):
            i = scan.statement(i + 1)
        elif token in ("if", "for", "case"):
            number += 1
            end, label, else_label = scan.construct(i)
            found.append(GenerateConstruct(number, token, label, else_label,
                                           " ".join(tokens[i:end])))
            i = end
        else:
            i += 1

    return found


class _TokenScanner:
    def __init__(self, tokens: list[str]):
        self.tokens = tokens

    def block(self, i: int) -> int:
        depth = 0

        while i < len(self.tokens):
            if self.tokens[i] in ("begin", "fork"):
                depth += 1
            elif self.tokens[i] in ("end", "join", "join_none", "join_any"):
                depth -= 1
                if depth == 0:
                    return i + 1
            i += 1

        return i

    def parens(self, i: int) -> int:
        depth = 0

        while i < len(self.tokens):
            depth += PAREN_DEPTH.get(self.tokens[i], 0)
            i += 1
            if depth == 0:
                return i

        return i

    def statement(self, i: int) -> int:
        while i < len(self.tokens) and self.tokens[i] in ("@", "#"):
            i = self.parens(i + 1) if self.tokens[i + 1] == "(" else i + 2

        while i < len(self.tokens) and self.tokens[i] != ";":
            if self.tokens[i] == "begin":
                return self.block(i)
            i += 1

        return i + 1

    def body(self, i: int) -> tuple[int, str | None]:
        if self.tokens[i] != "begin":
            return self.statement(i), None

        labelled = i + 2 < len(self.tokens) and self.tokens[i + 1] == ":"
        return self.block(i), self.tokens[i + 2] if labelled else None

    def construct(self, i: int) -> tuple[int, str | None, str | None]:
        end = self.parens(i + 1)
        if self.tokens[i] == "case":
            return self.tokens.index("endcase", end) + 1, None, None

        end, label = self.body(end)
        else_label = None

        while end < len(self.tokens) and self.tokens[end] == "else":
            end += 1
            if self.tokens[end] == "if":
                end = self.parens(end + 1)

            end, branch_label = self.body(end)
            else_label = branch_label or else_label

        return end, label, else_label


def _module_body(text: str, module: str) -> str:
    header = re.search(MODULE_HEADER.format(module), text)
    if not header:
        raise RtlError(f"module {module} not found")

    i = header.end()
    depth = 0
    while text[i] != ";" or depth:
        depth += PAREN_DEPTH.get(text[i], 0)
        i += 1

    return text[i + 1:text.find("endmodule", i)]


def _closing_paren(text: str, i: int) -> int:
    depth = 1
    while depth:
        depth += PAREN_DEPTH.get(text[i], 0)
        i += 1

    return i


def _sv_int(value: str) -> int:
    value = value.strip().replace("_", "")
    based = re.fullmatch(r"\d*'([hdbo])([0-9a-fA-F]+)", value)
    if not based:
        return int(value)

    return int(based.group(2), {"h": 16, "d": 10, "b": 2, "o": 8}[based.group(1)])
