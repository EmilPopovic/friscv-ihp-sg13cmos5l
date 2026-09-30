// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

// Both HyperRAMs through pads:
//   - word sweeps larger than the cache on each chip select
//   - the top of chip 1
//   - byte and halfword writes

.equ SCRATCH, 0x03000000
.equ HALT,    0x50000000
.equ PASS,    0xaabbccdd
.equ FAIL,    0xdeadbeef

.equ KEY,     0x5a0ff0a5
# chip_soc's MemSize is per chip: 32 MiB, CS1 at 0x8200_0000
.equ CHIP0,   0x80200000        # clear of this code
.equ CHIP1,   0x82200000        # CS1 at the same offset as CHIP0
.equ TOP1,    0x83fff000        # last 4 KiB of CS1
.equ SWEEP,   0x8000            # 32 KiB, larger than cache
.equ TOPLEN,  0x1000
.equ BYTES,   0x81010000
.equ BYTELEN, 64

.section .text.init
.global _start
_start:
    # Fill middle of CS0
    li   s0, CHIP0
    li   a1, SWEEP
    jal  ra, fill
    # Fill middle of CS1
    li   s0, CHIP1
    li   a1, SWEEP
    jal  ra, fill
    # Fill top of CS1
    li   s0, TOP1
    li   a1, TOPLEN
    jal  ra, fill

    # Check middle of CS0, middle of CS1, and top of CS1
    li   s0, CHIP0
    li   a1, SWEEP
    jal  ra, check
    li   s0, CHIP1
    li   a1, SWEEP
    jal  ra, check
    li   s0, TOP1
    li   a1, TOPLEN
    jal  ra, check

# byte i = 37 * i + 11, 0xbeef at every offset 2 mod 8
    li   s0, BYTES
    li   t0, 0
1:  slli t2, t0, 5
    slli t3, t0, 2
    add  t2, t2, t3
    add  t2, t2, t0
    addi t2, t2, 11
    add  t1, s0, t0
    sb   t2, 0(t1)
    addi t0, t0, 1
    li   t4, BYTELEN
    blt  t0, t4, 1b

    li   t0, 2
    li   t2, 0xbeef
2:  add  t1, s0, t0
    sh   t2, 0(t1)
    addi t0, t0, 8
    li   t4, BYTELEN
    blt  t0, t4, 2b

    # Evict cache to ensure reads from HyperRAM
    li   s0, CHIP0
    li   a1, SWEEP
    jal  ra, check

    li   s0, BYTES
    li   t0, 0
3:  add  t1, s0, t0
    lbu  t3, 0(t1)
    andi t4, t0, 7
    li   t5, 2
    beq  t4, t5, 4f
    li   t5, 3
    beq  t4, t5, 5f
    slli t2, t0, 5
    slli t5, t0, 2
    add  t2, t2, t5
    add  t2, t2, t0
    addi t2, t2, 11
    andi t2, t2, 0xff
    j    6f
4:  li   t2, 0xef
    j    6f
5:  li   t2, 0xbe
6:  bne  t2, t3, fail
    addi t0, t0, 1
    li   t4, BYTELEN
    blt  t0, t4, 3b

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

# s0 = base, a1 = bytes; word = address ^ KEY
fill:
    li   t6, KEY
    add  t1, s0, a1
    mv   t0, s0
1:  xor  t2, t0, t6
    sw   t2, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, 1b
    ret

check:
    li   t6, KEY
    add  t1, s0, a1
    mv   t0, s0
1:  xor  t2, t0, t6
    lw   t3, 0(t0)
    bne  t2, t3, fail
    addi t0, t0, 4
    bltu t0, t1, 1b
    ret
