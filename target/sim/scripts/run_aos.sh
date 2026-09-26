#!/usr/bin/env bash
# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
#
# Matej Jurasić <matej.jurasic@cappig.dev>
#
# Boot an apheleiaOS image on the SoC sim: scripts/run_aos.sh <image>

set -euo pipefail

[ $# -eq 1 ] && [ -f "$1" ] || { echo "usage: run_aos.sh <image>" >&2; exit 1; }
image=$(realpath "$1")
cd "$(dirname "$0")/.."

dir=obj_dir_aos
export FRISCV_UART_DIV=${UART_DIV:-27}
export FRISCV_TEST_CYCLES=${CYCLES:-20000000000}

mkdir -p $dir
make soc SOC_MEM_SIZE="${MEM_SIZE:-268435456}" SOC_DIR=$dir >/dev/null

if [ "${BOOT:-jtag}" = qspi ]; then
    sdk=$(bender path vernii)/sw/sdk
    riscv64-unknown-elf-gcc -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib \
        -Wl,--no-warn-rwx-segments -Wl,-Ttext=4 -o $dir/fsbl.elf "$sdk/loaders/fsbl.S"
    riscv64-unknown-elf-objcopy -O binary $dir/fsbl.elf $dir/fsbl.bin
    python3 "$sdk/tools/mkflash.py" $dir/fsbl.bin "$image" $dir/flash.bin
    exec ./$dir/friscv_soc qspiboot $dir/flash.bin
fi

python3 scripts/flat2elf.py "$image" $dir/aos.elf
FRISCV_LLCSEL=${LLCSEL:-0xf} exec ./$dir/friscv_soc test $dir/aos.elf
