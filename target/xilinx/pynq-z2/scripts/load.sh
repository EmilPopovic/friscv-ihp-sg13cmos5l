#!/usr/bin/env bash
# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Reconfigure the FPGA, then push an ELF to the bootloader from 'make
# bootloader'. Reconfiguring every time is required: the incoming image
# overwrites the trampoline at the reset vector.
#
#   scripts/load.sh prog.elf [--port /dev/ttyUSB0] [--baud 57600]

set -euo pipefail

target="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ $# -eq 0 ]; then
    echo "usage: load.sh prog.elf [uart_load.py options]" >&2
    exit 1
fi

echo "reconfiguring" >&2
make -C "$target" program >/dev/null ||
    { echo "programming failed, see build/vivado_program.log" >&2; exit 1; }

exec python3 "$target/scripts/uart_load.py" "$@"
