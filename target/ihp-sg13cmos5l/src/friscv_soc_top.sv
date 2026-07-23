// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/

// Based on https://github.com/IHP-GmbH/ihp-sg13cmos5l-librelane-template/blob/main/src/chip_top.sv

// ============================================================================
//  Pin  Signal          Type           | Pin  Signal          Type
//  ---  --------------  -------------- | ---  --------------  --------------
//    1  HB_DQ0          bidir          |  25  PA5/QSPI0_IO0   bidir
//    2  HB_DQ1          bidir          |  26  PA6/QSPI0_IO1   bidir
//    3  HB_DQ2          bidir          |  27  PA7/QSPI0_IO2   bidir (strap)
//    4  HB_DQ3          bidir          |  28  PA8/QSPI0_IO3   bidir (strap)
//    5  IOVDD           power          |  29  VSS             power
//    6  HB_DQ4          bidir          |  30  VDD             power
//    7  HB_DQ5          bidir          |  31  QSPI0_SCK/PA9   bidir
//    8  HB_DQ6          bidir          |  32  IOVSS           power
//    9  HB_DQ7          bidir          |  33  IOVDD           power
//   10  HB_RWDS         bidir          |  34  PA10/QSPI0_CS0  bidir
//   11  HB_CK           output         |  35  PA11/QSPI0_CS1  bidir
//   12  IOVSS           power          |  36  PA12/QSPI0_CS2  bidir
//   13  HB_CS0_N        output         |  37  TCK             input
//   14  HB_RST_N        output         |  38  TMS             input
//   15  VSS             power          |  39  TDI             input
//   16  CLK_OUT         output         |  40  TDO             output
//   17  VDD             power          |  41  VSS             power
//   18  PA0             bidir          |  42  VDD             power
//   19  PA1             bidir (irq)    |  43  UART0_TX        output
//   20  PA2             bidir (irq)    |  44  UART0_RX        input
//   21  IOVSS           power          |  45  RST_N           input
//   22  IOVDD           power          |  46  IOVSS           power
//   23  PA3             bidir (irq)    |  47  CLK             input
//   24  PA4             bidir (irq)    |  48  IOVDD           power
// ============================================================================

`default_nettype none

module friscv_soc_top #(
    // Power/ground pads for core
    parameter NUM_VDD_PADS = 3,    // pins 17, 33, 42
    parameter NUM_VSS_PADS = 3,    // pins 15, 32, 41

    // Power/ground pads for I/O
    parameter NUM_IOVDD_PADS = 4,  // pins 5, 22, 30, 48
    parameter NUM_IOVSS_PADS = 4,  // pins 12, 21, 29, 46

    // Signal pads
    parameter NUM_GPIO_PADS   = 13, // PA0..PA12 (GPIO / QSPI0 muxed)
    parameter NUM_HB_DQ_PADS  = 8,  // HB_DQ0..HB_DQ7
    parameter NUM_INPUT_PADS  = 4,  // TCK, TMS, TDI, UART0_RX
    parameter NUM_OUTPUT_PADS = 6,  // CLK_OUT, TDO, UART0_TX, HB_CK, HB_CS0_N, HB_RST_N
    parameter NUM_BIDIR_PADS  = NUM_GPIO_PADS + NUM_HB_DQ_PADS + 1  // + HB_RWDS = 22
) (
    `ifdef USE_POWER_PINS
    inout wire IOVDD,
    inout wire IOVSS,
    inout wire VDD,
    inout wire VSS,
    `endif
    inout wire clk_PAD,
    inout wire rst_n_PAD,
    inout wire [NUM_INPUT_PADS-1 :0] input_PAD,
    inout wire [NUM_OUTPUT_PADS-1:0] output_PAD,
    inout wire [NUM_BIDIR_PADS-1 :0] bidir_PAD
);

// ============================================================
// Pad array index map
// ============================================================

// Dedicated: clk_PAD (pin 47), rst_n_PAD (pin 45)

// input_PAD[]
localparam int IN_TCK     = 0;   // pin 37
localparam int IN_TMS     = 1;   // pin 38
localparam int IN_TDI     = 2;   // pin 39
localparam int IN_UART_RX = 3;   // pin 44

// output_PAD[]
localparam int OUT_CLK_OUT  = 0;  // pin 16
localparam int OUT_TDO      = 1;  // pin 40
localparam int OUT_UART_TX  = 2;  // pin 43
localparam int OUT_HB_CK    = 3;  // pin 11
localparam int OUT_HB_CS0_N = 4;  // pin 13
localparam int OUT_HB_RST_N = 5;  // pin 14

// bidir_PAD[]
localparam int BIDIR_PA_LSB    = 0;                                   // PA0     (pin 18)
localparam int BIDIR_PA_MSB    = NUM_GPIO_PADS - 1;                   // PA12    (pin 36)
localparam int BIDIR_HB_DQ_LSB = NUM_GPIO_PADS;                       // HB_DQ0  (pin 1)
localparam int BIDIR_HB_DQ_MSB = NUM_GPIO_PADS + NUM_HB_DQ_PADS - 1;  // HB_DQ7  (pin 9)
localparam int BIDIR_HB_RWDS   = NUM_BIDIR_PADS - 1;                  // HB_RWDS (pin 10)

wire clk_PAD2CORE;
wire rst_n_PAD2CORE;
wire [NUM_INPUT_PADS-1 :0] input_PAD2CORE;
wire [NUM_OUTPUT_PADS-1:0] output_CORE2PAD;
wire [NUM_BIDIR_PADS-1 :0] bidir_PAD2CORE;
wire [NUM_BIDIR_PADS-1 :0] bidir_CORE2PAD;
wire [NUM_BIDIR_PADS-1 :0] bidir_CORE2PAD_OE;

// Power/ground pad instances
generate
    // IOVDD pads
    for (genvar i = 0; i < NUM_IOVDD_PADS; i++) begin : iovdd_pads
        (* keep *)
        sg13cmos5l_IOPadIOVdd iovdd_pad (
            `ifdef USE_POWER_PINS
            .iovdd ( IOVDD ),
            .iovss ( IOVSS ),
            .vdd   ( VDD   ),
            .vss   ( VSS   )
            `endif
        );
    end

    // IOVSS pads
    for (genvar i = 0; i < NUM_IOVSS_PADS; i++) begin : iovss_pads
        (* keep *)
        sg13cmos5l_IOPadIOVss iovss_pad (
            `ifdef USE_POWER_PINS
            .iovdd ( IOVDD ),
            .iovss ( IOVSS ),
            .vdd   ( VDD   ),
            .vss   ( VSS   )
            `endif
        );
    end

    // VDD pads
    for (genvar i = 0; i < NUM_VDD_PADS; i++) begin : vdd_pads
        (* keep *)
        sg13cmos5l_IOPadVdd vdd_pad (
            `ifdef USE_POWER_PINS
            .iovdd ( IOVDD ),
            .iovss ( IOVSS ),
            .vdd   ( VDD   ),
            .vss   ( VSS   )
            `endif
        );
    end

    // VSS pads
    for (genvar i = 0; i < NUM_VSS_PADS; i++) begin : vss_pads
        (* keep *)
        sg13cmos5l_IOPadVss vss_pad (
            `ifdef USE_POWER_PINS
            .iovdd ( IOVDD ),
            .iovss ( IOVSS ),
            .vdd   ( VDD   ),
            .vss   ( VSS   )
            `endif
        );
    end
endgenerate

// Signal IO pad instances

// Schmitt trigger
sg13cmos5l_IOPadIn clk_pad (
    `ifdef USE_POWER_PINS
    .iovdd ( IOVDD ),
    .iovss ( IOVSS ),
    .vdd   ( VDD   ),
    .vss   ( VSS   ),
    `endif
    .p2c   ( clk_PAD2CORE ),
    .pad   ( clk_PAD      )
);

// Normal input
sg13cmos5l_IOPadIn rst_n_pad (
    `ifdef USE_POWER_PINS
    .iovdd ( IOVDD ),
    .iovss ( IOVSS ),
    .vdd   ( VDD   ),
    .vss   ( VSS   ),
    `endif
    .p2c   ( rst_n_PAD2CORE ),
    .pad   ( rst_n_PAD      )
);

// Input pads
generate
    for (genvar i = 0; i < NUM_INPUT_PADS; i++) begin : inputs
        sg13cmos5l_IOPadIn input_pad (
            `ifdef USE_POWER_PINS
            .iovdd  ( IOVDD ),
            .iovss  ( IOVSS ),
            .vdd    ( VDD   ),
            .vss    ( VSS   ),
            `endif
            .p2c    ( input_PAD2CORE[i] ),
            .pad    ( input_PAD[i]      )
        );
    end
endgenerate

// Output pads
generate
    for (genvar i = 0; i < NUM_OUTPUT_PADS; i++) begin : outputs
        sg13cmos5l_IOPadOut30mA output_pad (
            `ifdef USE_POWER_PINS
            .iovdd  ( IOVDD ),
            .iovss  ( IOVSS ),
            .vdd    ( VDD   ),
            .vss    ( VSS   ),
            `endif
            .c2p    ( output_CORE2PAD[i] ),
            .pad    ( output_PAD[i]      )
        );
    end
endgenerate

// Bidirectional pads
generate
    for (genvar i = 0; i < NUM_BIDIR_PADS; i++) begin : bidirs
        sg13cmos5l_IOPadInOut30mA bidir_pad (
            `ifdef USE_POWER_PINS
            .iovdd  ( IOVDD ),
            .iovss  ( IOVSS ),
            .vdd    ( VDD   ),
            .vss    ( VSS   ),
            `endif
            .c2p    ( bidir_CORE2PAD[i]    ),
            .c2p_en ( bidir_CORE2PAD_OE[i] ),
            .p2c    ( bidir_PAD2CORE[i]    ),
            .pad    ( bidir_PAD[i]         )
        );
    end
endgenerate

// HyperBus pad wiring
// DQ[7:0] and RWDS are bidirectional.
// A single output-enable drives all 8 DQ pads.
// CK, CS0_N and RST_N are output-only.

wire       hb_dq_oe;
wire [7:0] hb_dq_o;
wire [7:0] hb_dq_i;

assign bidir_CORE2PAD   [BIDIR_HB_DQ_MSB:BIDIR_HB_DQ_LSB] = hb_dq_o;
assign bidir_CORE2PAD_OE[BIDIR_HB_DQ_MSB:BIDIR_HB_DQ_LSB] = {NUM_HB_DQ_PADS{hb_dq_oe}};
assign hb_dq_i = bidir_PAD2CORE[BIDIR_HB_DQ_MSB:BIDIR_HB_DQ_LSB];

// Core design

(* keep *) friscv_soc #(
    .NumPads ( NUM_GPIO_PADS )
) friscv_soc_inst (
    .i_clk      ( clk_PAD2CORE   ),
    .i_rstn     ( rst_n_PAD2CORE ),

    .o_clk_out  ( output_CORE2PAD[OUT_CLK_OUT] ),

    .o_end      ( /* no package pin */ ),

    // UART0
    .i_uart_rx  ( input_PAD2CORE [IN_UART_RX]  ),
    .o_uart_tx  ( output_CORE2PAD[OUT_UART_TX] ),

    // JTAG
    .i_jtag_tck ( input_PAD2CORE [IN_TCK]  ),
    .i_jtag_tms ( input_PAD2CORE [IN_TMS]  ),
    .i_jtag_tdi ( input_PAD2CORE [IN_TDI]  ),
    .o_jtag_tdo ( output_CORE2PAD[OUT_TDO] ),

    // Muxed pads
    .pad_in_i   ( bidir_PAD2CORE   [BIDIR_PA_MSB:BIDIR_PA_LSB] ),
    .pad_out_o  ( bidir_CORE2PAD   [BIDIR_PA_MSB:BIDIR_PA_LSB] ),
    .pad_oe_o   ( bidir_CORE2PAD_OE[BIDIR_PA_MSB:BIDIR_PA_LSB] ),

    // HyperBus
    .o_hyper_ck      ( output_CORE2PAD[OUT_HB_CK]       ),
    .o_hyper_ck_n    ( /* no package pin */             ),
    .o_hyper_cs_n    ( output_CORE2PAD[OUT_HB_CS0_N]    ),
    .o_hyper_rwds    ( bidir_CORE2PAD   [BIDIR_HB_RWDS] ),
    .i_hyper_rwds    ( bidir_PAD2CORE   [BIDIR_HB_RWDS] ),
    .o_hyper_rwds_oe ( bidir_CORE2PAD_OE[BIDIR_HB_RWDS] ),
    .o_hyper_dq      ( hb_dq_o                          ),
    .i_hyper_dq      ( hb_dq_i                          ),
    .o_hyper_dq_oe   ( hb_dq_oe                         ),
    .o_hyper_reset_n ( output_CORE2PAD[OUT_HB_RST_N]    )
);

endmodule

`default_nettype wire
