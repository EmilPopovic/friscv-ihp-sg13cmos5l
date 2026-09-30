// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

// Check each GPIO in both directions
// Load from OCM to test JTAG load

.equ SCRATCH, 0x03000000
.equ HALT,    0x50000000
.equ PASS,    0xaabbccdd
.equ FAIL,    0xdeadbeef

.equ GPIO,       0x03030000
.equ DATA_IN,    0x10
.equ DIRECT_OUT, 0x14
.equ DIRECT_OE,  0x20

.equ SETTLE, 16

.section .text.init
.global _start
_start:
    li   s0, GPIO

    li   s3, 0x55
    sw   s3, DIRECT_OE(s0)
    jal  ra, walk
    li   s3, 0xaa
    sw   s3, DIRECT_OE(s0)
    jal  ra, walk

pass:
    li   t0, SCRATCH
    li   t1, PASS
    sw   t1, 0(t0)
    li   t0, HALT
    sw   zero, 0(t0)
9:  j    9b

fail:
    li   t0, SCRATCH
    li   t1, FAIL
    sw   t1, 0(t0)
    li   t0, HALT
    sw   zero, 0(t0)
8:  j    8b

walk:
    la   s1, patterns
    la   s2, patterns_end
1:  lw   t1, 0(s1)
    sw   t1, DIRECT_OUT(s0)
    li   t0, SETTLE
2:  addi t0, t0, -1
    bnez t0, 2b
    lw   t2, DATA_IN(s0)
    andi t2, t2, 0xff
    and  t3, t1, s3
    li   t4, 0x55
    beq  s3, t4, 3f
    srli t4, t3, 1
    j    4f
3:  slli t4, t3, 1
4:  or   t3, t3, t4
    bne  t2, t3, fail
    addi s1, s1, 4
    bltu s1, s2, 1b
    ret

.section .rodata
.align 2
patterns:
    .word 0x00, 0xff, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80
    .word 0x55, 0xaa, 0x5a, 0xa5, 0x0f, 0xf0
patterns_end:
