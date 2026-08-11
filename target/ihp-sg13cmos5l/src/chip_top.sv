// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/

// Based on https://github.com/IHP-GmbH/ihp-sg13cmos5l-librelane-template/blob/main/src/chip_top.sv

// ============================================================================
//  Pin  Signal  Type / function            | Pin  Signal    Type / function
//  ---  ------  -------------------------- | ---  --------  -------------------
//    1  PA13    bidir  HB_DQ0              |  25  PA5       bidir  QSPI0_IO0
//    2  PA14    bidir  HB_DQ1              |  26  PA6       bidir  QSPI0_IO1
//    3  PA15    bidir  HB_DQ2              |  27  PA7       bidir  QSPI0_IO2 (strap)
//    4  PA16    bidir  HB_DQ3              |  28  PA8       bidir  QSPI0_IO3 (strap)
//    5  IOVDD   power                      |  29  IOVSS     power
//    6  PA17    bidir  HB_DQ4              |  30  IOVDD     power
//    7  PA18    bidir  HB_DQ5              |  31  PA9       bidir  QSPI0_SCK
//    8  PA19    bidir  HB_DQ6              |  32  VSS       power
//    9  PA20    bidir  HB_DQ7              |  33  VDD       power
//   10  PA21    bidir  HB_RWDS             |  34  PA10      bidir  QSPI0_CS0
//   11  PA22    output HB_CK               |  35  PA11      bidir  QSPI0_CS1
//   12  IOVSS   power                      |  36  PA12      bidir  QSPI0_CS2
//   13  PA23    output HB_CS0_N            |  37  TCK       input
//   14  PA24    output HB_RST_N            |  38  TMS       input
//   15  VSS     power                      |  39  TDI       input
//   16  CLK_OUT output                     |  40  TDO       output
//   17  VDD     power                      |  41  VSS       power
//   18  PA0     bidir                      |  42  VDD       power
//   19  PA1     bidir (irq)                |  43  UART0_TX  output
//   20  PA2     bidir (irq)                |  44  UART0_RX  input
//   21  IOVSS   power                      |  45  RST_N     input
//   22  IOVDD   power                      |  46  IOVSS     power
//   23  PA3     bidir (irq)                |  47  CLK       input
//   24  PA4     bidir (irq)                |  48  IOVDD     power
// ============================================================================

`default_nettype none

module chip_top #(
    // Power/ground pads for core
    parameter NUM_VDD_PADS = 3,    // pins 17, 33, 42
    parameter NUM_VSS_PADS = 3,    // pins 15, 32, 41

    // Power/ground pads for I/O
    parameter NUM_IOVDD_PADS = 4,  // pins 5, 22, 30, 48
    parameter NUM_IOVSS_PADS = 4,  // pins 12, 21, 29, 46

    // Signal pads
    parameter NUM_GPIO_PADS   = 25, // PA0..PA24
    parameter NUM_INPUT_PADS  = 4,  // TCK, TMS, TDI, UART0_RX
    parameter NUM_OUTPUT_PADS = 3,  // CLK_OUT, TDO, UART0_TX
    parameter NUM_BIDIR_PADS  = NUM_GPIO_PADS  // PA0..PA24
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

// bidir_PAD[]: bidir_PAD[n]

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

// Core design

(* keep *) friscv_chip_soc #(
    .NumPads ( NUM_GPIO_PADS )
) soc_inst (
    .i_clk         ( clk_PAD2CORE                 ),
    .i_rstn        ( rst_n_PAD2CORE               ),

    .o_clk_out     ( output_CORE2PAD[OUT_CLK_OUT] ),

    .o_end         ( /* no package pin */         ),

    // UART0
    .i_uart_rx     ( input_PAD2CORE [IN_UART_RX]  ),
    .o_uart_tx     ( output_CORE2PAD[OUT_UART_TX] ),

    // JTAG
    .i_jtag_tck    ( input_PAD2CORE [IN_TCK]      ),
    .i_jtag_tms    ( input_PAD2CORE [IN_TMS]      ),
    .i_jtag_trstn  ( 1'b1                         ),
    .i_jtag_tdi    ( input_PAD2CORE [IN_TDI]      ),
    .o_jtag_tdo    ( output_CORE2PAD[OUT_TDO]     ),
    .o_jtag_tdo_oe ( /* no package pin */         ),

    // Muxed signals
    .pad_in_i      ( bidir_PAD2CORE               ),
    .pad_out_o     ( bidir_CORE2PAD               ),
    .pad_oe_o      ( bidir_CORE2PAD_OE            )
);

endmodule

`default_nettype wire
