// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Matej Jurasic <matej.jurasic@cappig.dev>

// tb_chip for the final netlist
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

RVSoC9108 dut (
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
assign gpio_a_oe_o[0] = dut.\gpio_a_pads[0].gpio_a_pad .c2p_en;
assign gpio_a_oe_o[1] = dut.\gpio_a_pads[1].gpio_a_pad .c2p_en;
assign gpio_a_oe_o[2] = dut.\gpio_a_pads[2].gpio_a_pad .c2p_en;
assign gpio_a_oe_o[3] = dut.\gpio_a_pads[3].gpio_a_pad .c2p_en;
assign gpio_a_oe_o[4] = dut.\gpio_a_pads[4].gpio_a_pad .c2p_en;
assign gpio_a_oe_o[5] = dut.\gpio_a_pads[5].gpio_a_pad .c2p_en;
assign gpio_a_oe_o[6] = dut.\gpio_a_pads[6].gpio_a_pad .c2p_en;
assign gpio_a_oe_o[7] = dut.\gpio_a_pads[7].gpio_a_pad .c2p_en;

assign qspi0_sd_oe_o[0] = dut.\qspi0_io_pads[0].qspi0_io_pad .c2p_en;
assign qspi0_sd_oe_o[1] = dut.\qspi0_io_pads[1].qspi0_io_pad .c2p_en;
assign qspi0_sd_oe_o[2] = dut.\qspi0_io_pads[2].qspi0_io_pad .c2p_en;
assign qspi0_sd_oe_o[3] = dut.\qspi0_io_pads[3].qspi0_io_pad .c2p_en;

for (genvar i = 0; i < NumGpio; i++) begin : gen_gpio
    assign gpio_a_pad[i] = gpio_a_tb_oe_i[i] ? gpio_a_i[i] : 1'bz;
    assign gpio_a_pad[i] = !(chip_oe[FloatGpio + i] || tb_oe[FloatGpio + i])
                         ? float_i[FloatGpio + i] : 1'bz;
    assign gpio_a_o[i]   = gpio_a_pad[i];
end

for (genvar i = 0; i < 4; i++) begin : gen_qspi
    assign qspi0_io_pad[i] = qspi0_sd_tb_oe_i[i] ? qspi0_sd_i[i] : 1'bz;
    assign qspi0_io_pad[i] = !(chip_oe[FloatQspi + i] || tb_oe[FloatQspi + i])
                           ? float_i[FloatQspi + i] : 1'bz;
    assign qspi0_sd_o[i]   = qspi0_io_pad[i];
end

// One enable to all DQ pads
assign hyper_dq_oe_o = dut.\hb_dq_pads[0].hb_dq_pad .c2p_en;

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

// The netlist has no core bus to watch and the end store faults into the ROM park loop,
// so end on PASS or FAIL in SCB.SCRATCH0, or when the ROM parks again

localparam logic [31:0] PassValue = 32'haabb_ccdd;
localparam logic [31:0] FailValue = 32'h0bad_c0de;
localparam logic [31:0] Parked    = 32'd1;

logic [31:0] scratch, scratch_q;
logic        end_q;
logic [31:0] result_q;

assign scratch = {
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[31] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[30] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[29] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[28] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[27] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[26] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[25] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[24] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[23] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[22] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[21] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[20] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[19] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[18] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[17] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[16] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[15] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[14] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[13] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[12] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[11] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[10] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[9] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[8] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[7] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[6] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[5] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[4] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[3] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[2] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[1] ,
    dut.\soc_inst.i_vernii_soc.i_scb.scratch0[0]
};

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        scratch_q <= '0;
        end_q     <= 1'b0;
        result_q  <= '0;
    end else begin
        scratch_q <= scratch;

        if (!end_q && scratch != scratch_q) begin
            if (scratch == PassValue || scratch == FailValue) begin
                end_q    <= 1'b1;
                result_q <= scratch;
            end else if (scratch == Parked && scratch_q != '0) begin
                end_q    <= 1'b1;
                result_q <= scratch_q;
            end
        end
    end
end

assign end_o    = end_q;
assign result_o = result_q;

endmodule
