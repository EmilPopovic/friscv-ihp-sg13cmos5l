// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Serial bootloader for CONFIG=preload. Lives at the top of SRAM and leaves a
// trampoline at the reset vector, so programs still link at 0x8000_0000.
//
// Frame: "FRSV" | u32 length | payload | u32 checksum, little endian.
// scripts/uart_load.py sends it.

#define UART_BASE    0x10000000
#define UART_RBR     0x00       // also THR, and DLL when LCR.DLAB = 1
#define UART_DLM     0x04
#define UART_LCR     0x0c
#define UART_LSR     0x14

// 25 MHz / (16 * 27) = 57870, +0.5% from 57600
#define UART_DIVISOR 27

#define LOAD_ADDR    0x80000000

    // Reset vector; the incoming program overwrites it
    .section .trampoline, "ax"
    .globl _start
_start:
    j       _boot

    .section .text
_boot:
    la      sp, _stack_top

    li      t0, UART_BASE
    li      t1, 0x80                // LCR.DLAB = 1
    sw      t1, UART_LCR(t0)
    li      t1, UART_DIVISOR
    sw      t1, UART_RBR(t0)        // DLL
    sw      zero, UART_DLM(t0)      // DLM
    li      t1, 0x03                // 8N1, DLAB = 0
    sw      t1, UART_LCR(t0)

    la      a0, banner
    jal     ra, puts

sync:
    la      a0, magic
    jal     ra, expect
    beqz    a0, sync

    jal     ra, get_u32             // length
    mv      s1, a0

    li      s0, LOAD_ADDR
    li      s2, 0                   // checksum accumulator

recv:
    beqz    s1, recv_done
    jal     ra, getc
    sb      a0, 0(s0)
    add     s2, s2, a0
    addi    s0, s0, 1
    addi    s1, s1, -1
    j       recv

recv_done:
    jal     ra, get_u32             // expected checksum
    bne     a0, s2, bad

    la      a0, ok
    jal     ra, puts
    li      t0, LOAD_ADDR
    jr      t0

bad:
    la      a0, err
    jal     ra, puts
    j       sync

// ---- expect: a0 = NUL-terminated string, returns 1 if it matched ----
expect:
    mv      s3, ra
    mv      t2, a0
1:  lbu     t3, 0(t2)
    beqz    t3, 2f
    jal     ra, getc
    bne     a0, t3, 3f
    addi    t2, t2, 1
    j       1b
2:  li      a0, 1
    mv      ra, s3
    ret
3:  li      a0, 0
    mv      ra, s3
    ret

// ---- get_u32: little endian, returns in a0 ----
get_u32:
    mv      s3, ra
    li      s4, 0
    li      t4, 0
1:  jal     ra, getc
    sll     a0, a0, t4
    or      s4, s4, a0
    addi    t4, t4, 8
    li      t5, 32
    blt     t4, t5, 1b
    mv      a0, s4
    mv      ra, s3
    ret

// ---- getc: blocks, returns the byte in a0 ----
getc:
    li      t0, UART_BASE
1:  lw      t1, UART_LSR(t0)
    andi    t1, t1, 0x01            // LSR.DR
    beqz    t1, 1b
    lbu     a0, UART_RBR(t0)
    ret

// ---- putc: a0 = character ----
// Does not poll LSR.THRE: obi_uart leaves it stuck high (the clear at
// obi_uart_tx.sv:141 is overridden at :285), so a poll never waits.
putc:
    li      t0, UART_BASE
    sb      a0, UART_RBR(t0)
    li      t1, 800
1:  addi    t1, t1, -1
    bnez    t1, 1b
    ret

// ---- puts: a0 = NUL-terminated string ----
puts:
    mv      s5, ra
    mv      s6, a0
1:  lbu     a0, 0(s6)
    beqz    a0, 2f
    jal     ra, putc
    addi    s6, s6, 1
    j       1b
2:  mv      ra, s5
    ret

    .section .rodata
banner:
    .asciz  "\r\nFRISCV boot 57600 8N1, waiting for image\r\n"
magic:
    .asciz  "FRSV"
ok:
    .asciz  "OK\r\n"
err:
    .asciz  "BAD CHECKSUM\r\n"

    .section .bss
    .align 4
    .space 512
_stack_top:
