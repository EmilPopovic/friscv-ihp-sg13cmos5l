/* Copyright 2026 FER, HPC Architecture and Application Research Center
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 *
 * .text.init comes first: the core resets to the base of the memory region, so
 * the entry point has to be the first byte. scripts/elf2mem.py enforces it.
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 512K
}

SECTIONS {
    .text : {
        *(.text.init)
        *(.text)
        *(.text.*)
    } > RAM

    .rodata : {
        . = ALIGN(4);
        *(.rodata)
        *(.rodata.*)
    } > RAM

    .data : {
        . = ALIGN(4);
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
    } > RAM

    .bss : {
        . = ALIGN(4);
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        *(COMMON)
    } > RAM

    _end = .;
}
