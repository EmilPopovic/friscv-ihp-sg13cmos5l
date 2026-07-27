/* Copyright 2026 FER, HPC Architecture and Application Research Center
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 *
 * Links the serial bootloader: a trampoline at the reset vector and the loader
 * at the top of SRAM, so an incoming program can use 0x8000_0000 upwards. The
 * largest riscv-arch-test binary reaches 0x8003_f200.
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
    TRAMP (rx)  : ORIGIN = 0x80000000, LENGTH = 16
    BOOT  (rwx) : ORIGIN = 0x80070000, LENGTH = 64K
}

SECTIONS {
    .trampoline : { *(.trampoline) } > TRAMP

    .text : {
        *(.text)
        *(.text.*)
    } > BOOT

    .rodata : {
        . = ALIGN(4);
        *(.rodata)
        *(.rodata.*)
    } > BOOT

    .bss : {
        . = ALIGN(4);
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > BOOT
}
