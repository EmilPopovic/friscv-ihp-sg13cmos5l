// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Emil Popovic <mail@emilpopovic.me>

// Pad-level testbench for the chip top module meant for a 4-state simulator.
module tb_chip #(
    parameter int unsigned NumGpio   = 8,
    parameter int unsigned NumBoot   = 2,
    parameter int unsigned NumQspiCs = 3,
    parameter int unsigned NumHbCs   = 2
) (
    input  logic clk_i,
    input  logic rst_ni,

    output logic        end_o,
    output logic [31:0] result_o,

    input  logic jtag_tck_i,
    input  logic jtag_tms_i,
    input  logic jtag_tdi_i,
    input  logic jtag_trst_ni,
    output logic jtag_tdo_o,

    input  logic uart0_rx_i,
    output logic uart0_tx_o,

    output logic heartbeat_o,

    input  logic [NumBoot-1:0] boot_sel_i,

    output logic [NumGpio-1:0] gpio_a_o,
    output logic [NumGpio-1:0] gpio_a_oe_o,
    input  logic [NumGpio-1:0] gpio_a_i,
    input  logic [NumGpio-1:0] gpio_a_tb_oe_i,

    output logic                 qspi0_sck_o,
    output logic [NumQspiCs-1:0] qspi0_cs_o,
    output logic [3:0]           qspi0_sd_o,
    output logic [3:0]           qspi0_sd_oe_o,
    input  logic [3:0]           qspi0_sd_i,
    input  logic [3:0]           qspi0_sd_tb_oe_i,

    output logic [7:0]         hyper_dq_o,
    output logic               hyper_dq_oe_o,
    input  logic [7:0]         hyper_dq_i,
    input  logic               hyper_dq_tb_oe_i,
    output logic               hyper_rwds_o,
    output logic               hyper_rwds_oe_o,
    input  logic               hyper_rwds_i,
    input  logic               hyper_rwds_tb_oe_i,
    output logic               hyper_ck_o,
    output logic [NumHbCs-1:0] hyper_cs_no,
    output logic               hyper_reset_no,

    input  logic [31:0] float_i,
    output logic [31:0] contention_o
);

localparam int unsigned FloatGpio = 0;
localparam int unsigned FloatQspi = 8;
localparam int unsigned FloatDq   = 12;
localparam int unsigned FloatRwds = 20;

wire clk_pad        = clk_i;
wire rst_n_pad      = rst_ni;
wire jtag_tck_pad   = jtag_tck_i;
wire jtag_tms_pad   = jtag_tms_i;
wire jtag_tdi_pad   = jtag_tdi_i;
wire jtag_trst_pad  = jtag_trst_ni;
wire uart0_rx_pad   = uart0_rx_i;
wire [NumBoot-1:0] boot_pad = boot_sel_i;

wire jtag_tdo_pad;
wire uart0_tx_pad;
wire heartbeat_pad;
wire qspi0_sck_pad;
wire [NumQspiCs-1:0] qspi0_cs_pad;
wire hb_ck_pad;
wire [NumHbCs-1:0] hb_cs_pad;
wire hb_rst_pad;

wire [NumGpio-1:0] gpio_a_pad;
wire [3:0]         qspi0_io_pad;
wire [7:0]         hb_dq_pad;
wire               hb_rwds_pad;

RVSoC9108 #(
    .NUM_GPIO_PADS ( NumGpio   ),
    .NUM_BOOT_PADS ( NumBoot   ),
    .NUM_QSPI_CS   ( NumQspiCs ),
    .NUM_HB_CS     ( NumHbCs   )
) dut (
    .clk_PAD         ( clk_pad       ),
    .rst_n_PAD       ( rst_n_pad     ),
    .heartbeat_PAD   ( heartbeat_pad ),
    .jtag_tck_PAD    ( jtag_tck_pad  ),
    .jtag_tms_PAD    ( jtag_tms_pad  ),
    .jtag_tdi_PAD    ( jtag_tdi_pad  ),
    .jtag_trst_n_PAD ( jtag_trst_pad ),
    .jtag_tdo_PAD    ( jtag_tdo_pad  ),
    .uart0_rx_PAD    ( uart0_rx_pad  ),
    .uart0_tx_PAD    ( uart0_tx_pad  ),
    .boot_PAD        ( boot_pad      ),
    .gpio_a_PAD      ( gpio_a_pad    ),
    .qspi0_io_PAD    ( qspi0_io_pad  ),
    .qspi0_sck_PAD   ( qspi0_sck_pad ),
    .qspi0_cs_PAD    ( qspi0_cs_pad  ),
    .hb_dq_PAD       ( hb_dq_pad     ),
    .hb_rwds_PAD     ( hb_rwds_pad   ),
    .hb_ck_PAD       ( hb_ck_pad     ),
    .hb_cs_PAD       ( hb_cs_pad     ),
    .hb_rst_PAD      ( hb_rst_pad    )
);

assign jtag_tdo_o     = jtag_tdo_pad;
assign uart0_tx_o     = uart0_tx_pad;
assign heartbeat_o    = heartbeat_pad;
assign qspi0_sck_o    = qspi0_sck_pad;
assign qspi0_cs_o     = qspi0_cs_pad;
assign hyper_ck_o     = hb_ck_pad;
assign hyper_cs_no    = hb_cs_pad;
assign hyper_reset_no = hb_rst_pad;

///////////////////
// Bidirectional //
///////////////////

logic [31:0] chip_oe, tb_oe;

always_comb begin
    chip_oe = '0;
    tb_oe   = '0;

    for (int unsigned i = 0; i < NumGpio; i++) begin
        tb_oe[FloatGpio + i] = gpio_a_tb_oe_i[i];
    end
    for (int unsigned i = 0; i < 4; i++) begin
        tb_oe[FloatQspi + i] = qspi0_sd_tb_oe_i[i];
    end
    for (int unsigned i = 0; i < 8; i++) begin
        tb_oe[FloatDq + i] = hyper_dq_tb_oe_i;
    end
    tb_oe[FloatRwds] = hyper_rwds_tb_oe_i;

    chip_oe[FloatGpio +: NumGpio] = gpio_a_oe_o;
    chip_oe[FloatQspi +: 4]       = qspi0_sd_oe_o;
    chip_oe[FloatDq   +: 8]       = {8{hyper_dq_oe_o}};
    chip_oe[FloatRwds]            = hyper_rwds_oe_o;
end

assign contention_o = chip_oe & tb_oe;

// Output enables from the pad cells
for (genvar i = 0; i < NumGpio; i++) begin : gen_gpio
    assign gpio_a_oe_o[i] = dut.gpio_a_pads[i].gpio_a_pad.c2p_en;
    assign gpio_a_pad[i]  = gpio_a_tb_oe_i[i] ? gpio_a_i[i] : 1'bz;
    assign gpio_a_pad[i]  = !(chip_oe[FloatGpio + i] || tb_oe[FloatGpio + i])
                          ? float_i[FloatGpio + i] : 1'bz;
    assign gpio_a_o[i]    = gpio_a_pad[i];
end

for (genvar i = 0; i < 4; i++) begin : gen_qspi
    assign qspi0_sd_oe_o[i] = dut.qspi0_io_pads[i].qspi0_io_pad.c2p_en;
    assign qspi0_io_pad[i]  = qspi0_sd_tb_oe_i[i] ? qspi0_sd_i[i] : 1'bz;
    assign qspi0_io_pad[i]  = !(chip_oe[FloatQspi + i] || tb_oe[FloatQspi + i])
                            ? float_i[FloatQspi + i] : 1'bz;
    assign qspi0_sd_o[i]    = qspi0_io_pad[i];
end

// One enable to all DQ pads
assign hyper_dq_oe_o = dut.hb_dq_pads[0].hb_dq_pad.c2p_en;

for (genvar i = 0; i < 8; i++) begin : gen_dq
    assign hb_dq_pad[i]  = hyper_dq_tb_oe_i ? hyper_dq_i[i] : 1'bz;
    assign hb_dq_pad[i]  = !(chip_oe[FloatDq + i] || tb_oe[FloatDq + i])
                         ? float_i[FloatDq + i] : 1'bz;
    assign hyper_dq_o[i] = hb_dq_pad[i];
end

assign hyper_rwds_oe_o = dut.hb_rwds_pad.c2p_en;
assign hb_rwds_pad     = hyper_rwds_tb_oe_i ? hyper_rwds_i : 1'bz;
assign hb_rwds_pad     = !(chip_oe[FloatRwds] || tb_oe[FloatRwds])
                       ? float_i[FloatRwds] : 1'bz;
assign hyper_rwds_o    = hb_rwds_pad;

/////////////////
// End of test //
/////////////////

// Result stored to SCB.SCRATCH0, end signaled by writing to END_ADDRESS = 0x5000_0000

localparam logic [31:0] EndAddress     = 32'h5000_0000;
localparam logic [31:0] ScratchAddress = 32'h0300_0000;

logic        store;
logic [31:0] store_addr;
logic        end_q;
logic [31:0] result_q;

assign store      = dut.soc_inst.i_vernii_soc.i_cpu.data_en &&
                    dut.soc_inst.i_vernii_soc.i_cpu.data_wr;
assign store_addr = dut.soc_inst.i_vernii_soc.i_cpu.data_addr;

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        end_q    <= 1'b0;
        result_q <= '0;
    end else if (!end_q && store) begin
        if (store_addr == EndAddress) begin
            end_q <= 1'b1;
        end else if (store_addr == ScratchAddress) begin
            result_q <= dut.soc_inst.i_vernii_soc.i_cpu.data_wdata;
        end
    end
end

assign end_o    = end_q;
assign result_o = result_q;

endmodule
