// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/

// Based on https://github.com/IHP-GmbH/ihp-sg13cmos5l-librelane-template/blob/main/src/chip_top.sv

`default_nettype none

module friscv_soc_top #(
    // Power/ground pads for core
    parameter NUM_VDD_PADS = 3,
    parameter NUM_VSS_PADS = 3,

    // Power/ground pads for I/O
    parameter NUM_IOVDD_PADS = 4,
    parameter NUM_IOVSS_PADS = 4,

    // Signal pads
    parameter NUM_INPUT_PADS  = 4,  // TCK, TMS, TDI, UART0_RX
    parameter NUM_OUTPUT_PADS = 3,  // CLK_OUT, TDO, UART0_TX
    parameter NUM_BIDIR_PADS  = 25
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

(* keep *) friscv_soc #(

) friscv_soc_inst (

);

endmodule

`default_nettype wire
