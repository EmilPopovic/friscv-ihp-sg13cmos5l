// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Matej Jurasic <matej.jurasic@cappig.dev>

`timescale 1ns/1ps

module tb_gls;

reg        clk_i              = 1'b0;
reg        rst_ni             = 1'b0;
reg        jtag_tck_i         = 1'b0;
reg        jtag_tms_i         = 1'b1;
reg        jtag_tdi_i         = 1'b0;
reg        jtag_trst_ni       = 1'b1;
reg        uart0_rx_i         = 1'b1;
reg  [1:0] boot_sel_i         = '0;
reg  [7:0] gpio_a_i           = '0;
reg  [7:0] gpio_a_tb_oe_i     = '0;
reg  [3:0] qspi0_sd_i         = '0;
reg  [3:0] qspi0_sd_tb_oe_i   = '0;
reg  [7:0] hyper_dq_i         = '0;
reg        hyper_dq_tb_oe_i   = 1'b0;
reg        hyper_rwds_i       = 1'b0;
reg        hyper_rwds_tb_oe_i = 1'b0;
reg [31:0] float_i            = '0;

wire        end_o;
wire [31:0] result_o;
wire        jtag_tdo_o;
wire        uart0_tx_o;
wire        heartbeat_o;
wire  [7:0] gpio_a_o;
wire  [7:0] gpio_a_oe_o;
wire        qspi0_sck_o;
wire  [2:0] qspi0_cs_o;
wire  [3:0] qspi0_sd_o;
wire  [3:0] qspi0_sd_oe_o;
wire  [7:0] hyper_dq_o;
wire        hyper_dq_oe_o;
wire        hyper_rwds_o;
wire        hyper_rwds_oe_o;
wire        hyper_ck_o;
wire  [1:0] hyper_cs_no;
wire        hyper_reset_no;
wire [31:0] contention_o;

tb_chip dut (
    .clk_i              ( clk_i              ),
    .rst_ni             ( rst_ni             ),
    .end_o              ( end_o              ),
    .result_o           ( result_o           ),
    .jtag_tck_i         ( jtag_tck_i         ),
    .jtag_tms_i         ( jtag_tms_i         ),
    .jtag_tdi_i         ( jtag_tdi_i         ),
    .jtag_trst_ni       ( jtag_trst_ni       ),
    .jtag_tdo_o         ( jtag_tdo_o         ),
    .uart0_rx_i         ( uart0_rx_i         ),
    .uart0_tx_o         ( uart0_tx_o         ),
    .heartbeat_o        ( heartbeat_o        ),
    .boot_sel_i         ( boot_sel_i         ),
    .gpio_a_o           ( gpio_a_o           ),
    .gpio_a_oe_o        ( gpio_a_oe_o        ),
    .gpio_a_i           ( gpio_a_i           ),
    .gpio_a_tb_oe_i     ( gpio_a_tb_oe_i     ),
    .qspi0_sck_o        ( qspi0_sck_o        ),
    .qspi0_cs_o         ( qspi0_cs_o         ),
    .qspi0_sd_o         ( qspi0_sd_o         ),
    .qspi0_sd_oe_o      ( qspi0_sd_oe_o      ),
    .qspi0_sd_i         ( qspi0_sd_i         ),
    .qspi0_sd_tb_oe_i   ( qspi0_sd_tb_oe_i   ),
    .hyper_dq_o         ( hyper_dq_o         ),
    .hyper_dq_oe_o      ( hyper_dq_oe_o      ),
    .hyper_dq_i         ( hyper_dq_i         ),
    .hyper_dq_tb_oe_i   ( hyper_dq_tb_oe_i   ),
    .hyper_rwds_o       ( hyper_rwds_o       ),
    .hyper_rwds_oe_o    ( hyper_rwds_oe_o    ),
    .hyper_rwds_i       ( hyper_rwds_i       ),
    .hyper_rwds_tb_oe_i ( hyper_rwds_tb_oe_i ),
    .hyper_ck_o         ( hyper_ck_o         ),
    .hyper_cs_no        ( hyper_cs_no        ),
    .hyper_reset_no     ( hyper_reset_no     ),
    .float_i            ( float_i            ),
    .contention_o       ( contention_o       )
);

endmodule
