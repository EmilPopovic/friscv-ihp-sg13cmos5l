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
# Build apheleiaOS if needed and boot it: scripts/aos.sh [rebuild]

set -euo pipefail
cd "$(dirname "$0")/.."

src=${AOS_DIR:-build_aos}/apheleiaOS
repo=${AOS_REPO:-https://github.com/cappig/apheleiaOS.git}

[ "${1:-}" = rebuild ] && rm -f "$src"/bin/apheleia_*_riscv_32.img

if ! ls "$src"/bin/apheleia_*_riscv_32.img >/dev/null 2>&1; then
    [ -d "$src/.git" ] || git clone --depth 1 "$repo" "$src"
    make -C "$src" all ARCH=riscv_32 TOOLCHAIN=llvm RISCV_FRISC=true
fi

exec scripts/run_aos.sh "$(ls "$src"/bin/apheleia_*_riscv_32.img | head -1)"
