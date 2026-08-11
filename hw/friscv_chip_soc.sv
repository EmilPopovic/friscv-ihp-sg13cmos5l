// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/

`timescale 1ns/1ps

module friscv_chip_soc import vernii_pkg::*; #(
    parameter int unsigned SramBase          = 32'h0000_0000,
    parameter int unsigned SramSize          = 32'h0000_2000,
    parameter int unsigned MemBase           = 32'h8000_0000,
    parameter int unsigned MemSize           = 32'h0100_0000,
    parameter int unsigned LineBytes         = 32,
    parameter int unsigned Ways              = 4,
    parameter bit          SramTags          = 1'b1,
    parameter bit          HyperClockDelayed = 1'b1,
    parameter int unsigned NumPads           = 25,
    parameter bit          EnablePlic        = 1,
    parameter int unsigned ZsblRomSizeBytes  = 144
) (
    input  logic  i_clk,
    input  logic  i_rstn,

    output logic  o_clk_out,

    output logic  o_end,

    // UART
    input  logic  i_uart_rx,
    output logic  o_uart_tx,

    // JTAG
    input  logic  i_jtag_tck,
    input  logic  i_jtag_tms,
    input  logic  i_jtag_trstn,
    input  logic  i_jtag_tdi,
    output logic  o_jtag_tdo,
    output logic  o_jtag_tdo_oe,

    // GPIO Port A muxed pads (PA0..PA24)
    input  logic [NumPads-1:0] pad_in_i,
    output logic [NumPads-1:0] pad_out_o,
    output logic [NumPads-1:0] pad_oe_o
);

// Output clock as heartbeat, do not use as real clock
logic [6:0] clk_div;
always_ff @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) clk_div <= '0;
    else         clk_div <= clk_div + 1;
end
assign o_clk_out = clk_div[6];

localparam int unsigned NumMuxPads = 13;
localparam int unsigned NumAfs     = 2;

localparam int unsigned PadHbDqLsb = 13;  // PA13..PA20 = HB_DQ0..HB_DQ7
localparam int unsigned PadHbRwds  = 21;  // PA21 = HB_RWDS
localparam int unsigned PadHbCk    = 22;  // PA22 = HB_CK
localparam int unsigned PadHbCsN   = 23;  // PA23 = HB_CS0_N
localparam int unsigned PadHbRstN  = 24;  // PA24 = HB_RST_N

localparam int unsigned Qspi0NumCs   = 3;  // CS0, CS1, CS2
localparam int unsigned Qspi0PadBase = 5;  // First muxed pad (PA5 = IO0)

localparam int unsigned PinmuxSlv   = 0;
localparam int unsigned HyperCfgSlv = 1;
localparam int unsigned NumExtRegSlv = 2;

localparam logic [31:0] PinmuxBaseAddr   = 32'h4000_1000;
localparam logic [31:0] PinmuxSize       = 32'h0000_1000;
localparam logic [31:0] HyperCfgBaseAddr = 32'h5001_0000;
localparam logic [31:0] HyperCfgSize     = 32'h0000_1000;

localparam axi_pkg::xbar_rule_32_t [NumExtRegSlv-1:0] ExtRegSlvRules = '{
    '{ idx: HyperCfgSlv, start_addr: HyperCfgBaseAddr, end_addr: HyperCfgBaseAddr + HyperCfgSize },
    '{ idx: PinmuxSlv,   start_addr: PinmuxBaseAddr,   end_addr: PinmuxBaseAddr + PinmuxSize }
};

logic por_rstn, soc_rstn;

vernii_axi_req_t  axi_mem_req;
vernii_axi_resp_t axi_mem_rsp;

vernii_reg_req_t [NumExtRegSlv-1:0] reg_ext_req;
vernii_reg_rsp_t [NumExtRegSlv-1:0] reg_ext_rsp;

logic [31:0] gpio_in, gpio_out, gpio_oe;

logic                  qspi0_sck, qspi0_sck_oe;
logic [Qspi0NumCs-1:0] qspi0_cs,  qspi0_cs_oe;
logic [3:0]            qspi0_sd_i, qspi0_sd_o, qspi0_sd_oe;

vernii_soc #(
    .SramBase         ( SramBase         ),
    .SramSize         ( SramSize         ),
    .MemBase          ( MemBase          ),
    .MemSize          ( MemSize          ),
    .LineBytes        ( LineBytes        ),
    .Ways             ( Ways             ),
    .SramTags         ( SramTags         ),
    .EnablePlic       ( EnablePlic       ),
    .ZsblRomSizeBytes ( ZsblRomSizeBytes ),
    .NumStraps        ( NumMuxPads       ),
    .NumExtRegSlv     ( NumExtRegSlv     ),
    .ExtRegSlvRules   ( ExtRegSlvRules   )
) i_vernii_soc (
    .i_clk         ( i_clk                   ),
    .i_rstn        ( i_rstn                  ),
    .o_por_rstn    ( por_rstn                ),
    .o_soc_rstn    ( soc_rstn                ),
    .o_end         ( o_end                   ),
    .o_axi_mem_req ( axi_mem_req             ),
    .i_axi_mem_rsp ( axi_mem_rsp             ),
    .o_reg_ext_req ( reg_ext_req             ),
    .i_reg_ext_rsp ( reg_ext_rsp             ),
    .i_strap       ( pad_in_i[NumMuxPads-1:0]),
    .i_uart_rx     ( i_uart_rx               ),
    .o_uart_tx     ( o_uart_tx               ),
    .i_jtag_tck    ( i_jtag_tck              ),
    .i_jtag_tms    ( i_jtag_tms              ),
    .i_jtag_trstn  ( i_jtag_trstn            ),
    .i_jtag_tdi    ( i_jtag_tdi              ),
    .o_jtag_tdo    ( o_jtag_tdo              ),
    .o_jtag_tdo_oe ( o_jtag_tdo_oe           ),
    .o_qspi_sck    ( qspi0_sck               ),
    .o_qspi_sck_oe ( qspi0_sck_oe            ),
    .o_qspi_cs     ( qspi0_cs                ),
    .o_qspi_cs_oe  ( qspi0_cs_oe             ),
    .o_qspi_sd     ( qspi0_sd_o              ),
    .o_qspi_sd_oe  ( qspi0_sd_oe             ),
    .i_qspi_sd     ( qspi0_sd_i              ),
    .i_gpio        ( gpio_in                 ),
    .o_gpio        ( gpio_out                ),
    .o_gpio_oe     ( gpio_oe                 )
);

// ============================================================
// Pin mux
// ============================================================

/*
Pad   AF0        AF1        Notes
----  ---------  ---------  -------------------------
PA0   gpio[0]    -
PA1   gpio[1]    -          external interrupt
PA2   gpio[2]    -          external interrupt
PA3   gpio[3]    -          external interrupt
PA4   gpio[4]    -          external interrupt
PA5   gpio[5]    QSPI0_IO0
PA6   gpio[6]    QSPI0_IO1
PA7   gpio[7]    QSPI0_IO2  boot strap
PA8   gpio[8]    QSPI0_IO3  boot strap
PA9   gpio[9]    QSPI0_SCK
PA10  gpio[10]   QSPI0_CS0
PA11  gpio[11]   QSPI0_CS1
PA12  gpio[12]   QSPI0_CS2
*/

logic [NumMuxPads-1:0][NumAfs-1:0] to_func;
logic [NumMuxPads-1:0][NumAfs-1:0] from_func;
logic [NumMuxPads-1:0][NumAfs-1:0] oe_func;

logic [NumMuxPads-1:0] pm_pad_out, pm_pad_oe;

// Region-relative pinmux register address
vernii_reg_req_t pinmux_req;
always_comb begin
    pinmux_req      = reg_ext_req[PinmuxSlv];
    pinmux_req.addr = reg_ext_req[PinmuxSlv].addr & (PinmuxSize - 1);
end

friscv_pinmux #(
    .NumPads  ( NumMuxPads       ),
    .NumAfs   ( NumAfs           ),
    .AfInIdle ( '0               ),  // Idle level presented to non-selected AFs, all 0
    .reg_req_t( vernii_reg_req_t ),
    .reg_rsp_t( vernii_reg_rsp_t )
 ) pinmux (
    .clk_i      ( i_clk                     ),
    .rst_ni     ( por_rstn                  ),
    .reg_req_i  ( pinmux_req                ),
    .reg_rsp_o  ( reg_ext_rsp[PinmuxSlv]    ),
    .pad_in_i   ( pad_in_i[NumMuxPads-1:0]  ),
    .pad_out_o  ( pm_pad_out                ),
    .pad_oe_o   ( pm_pad_oe                 ),
    .func_out_i ( from_func                 ),  // peripheral -> pinmux
    .func_in_o  ( to_func                   ),  // peripheral <- pinmux
    .func_oe_i  ( oe_func                   )
);

// GPIO on AF0
for (genvar p = 0; p < NumMuxPads; p++) begin : gen_gpio_af0
    assign from_func[p][0] = gpio_out[p];
    assign oe_func  [p][0] = gpio_oe [p];
    assign gpio_in[p]      = to_func[p][0];
end

assign gpio_in[31:NumMuxPads] = '0;

// Data lines PA5..PA8 (bidirectional)
for (genvar i = 0; i < 4; i++) begin : gen_qspi0_io
    assign from_func[Qspi0PadBase + i][1] = qspi0_sd_o [i];
    assign oe_func  [Qspi0PadBase + i][1] = qspi0_sd_oe[i];
    assign qspi0_sd_i[i]                  = to_func[Qspi0PadBase + i][1];
end

// SCK on PA9 (output only)
assign from_func[9][1] = qspi0_sck;
assign oe_func  [9][1] = qspi0_sck_oe;

// Chip selects PA10..PA12 (outputs only)
for (genvar i = 0; i < Qspi0NumCs; i++) begin : gen_qspi0_cs
    assign from_func[10 + i][1] = qspi0_cs   [i];
    assign oe_func  [10 + i][1] = qspi0_cs_oe[i];
end

// Pads PA0..PA4 have no alternate function, AF1 idle
for (genvar p = 0; p < Qspi0PadBase; p++) begin : gen_no_af1
    assign from_func[p][1] = 1'b0;
    assign oe_func  [p][1] = 1'b0;
end

// ============================================================
// External memory
// ============================================================

logic       hb_ck, hb_ck_n, hb_cs_n, hb_reset_n;
logic       hb_rwds_o, hb_rwds_i, hb_rwds_oe;
logic [7:0] hb_dq_o, hb_dq_i;
logic       hb_dq_oe;

localparam int unsigned HyperNumPhys    = 1;
localparam int unsigned HyperMinFreqMHz = 40;

// Requests past the mask alias onto low addresses instead of faulting
function automatic hyperbus_pkg::hyper_cfg_t hyper_rst_cfg();
    hyper_rst_cfg = hyperbus_pkg::gen_RstCfg(HyperNumPhys, HyperMinFreqMHz);
    hyper_rst_cfg.address_mask_msb = 5'($clog2(MemSize));
endfunction

hyperbus #(
    .NumChips        ( 1                       ),
    .NumPhys         ( HyperNumPhys            ),
    .RstCfg          ( hyper_rst_cfg()         ),
    .IsClockODelayed ( HyperClockDelayed       ),
    .AxiAddrWidth    ( AddrWidth               ),
    .AxiDataWidth    ( DataWidth               ),
    .AxiIdWidth      ( AxiIdWidth              ),
    .AxiUserWidth    ( AxiUserWidth            ),
    .axi_req_t       ( vernii_axi_req_t        ),
    .axi_rsp_t       ( vernii_axi_resp_t       ),
    .axi_w_chan_t    ( vernii_axi_w_chan_t     ),
    .axi_b_chan_t    ( vernii_axi_b_chan_t     ),
    .axi_ar_chan_t   ( vernii_axi_ar_chan_t    ),
    .axi_r_chan_t    ( vernii_axi_r_chan_t     ),
    .axi_aw_chan_t   ( vernii_axi_aw_chan_t    ),
    .RegAddrWidth    ( 32                      ),
    .RegDataWidth    ( 32                      ),
    .reg_req_t       ( vernii_reg_req_t        ),
    .reg_rsp_t       ( vernii_reg_rsp_t        ),
    .axi_rule_t      ( axi_pkg::xbar_rule_32_t ),
    .MinFreqMHz      ( HyperMinFreqMHz         ),
    .RstChipBase     ( MemBase                 ),
    .RstChipSpace    ( MemSize                 ),
    .AxiLogDepth     ( 1                       )
) i_hyperbus (
    .clk_phy_i       ( i_clk                    ),
    .rst_phy_ni      ( soc_rstn                 ),
    .clk_sys_i       ( i_clk                    ),
    .rst_sys_ni      ( soc_rstn                 ),
    .test_mode_i     ( 1'b0                     ),
    .axi_req_i       ( axi_mem_req              ),
    .axi_rsp_o       ( axi_mem_rsp              ),
    .reg_req_i       ( reg_ext_req[HyperCfgSlv] ),
    .reg_rsp_o       ( reg_ext_rsp[HyperCfgSlv] ),
    .hyper_cs_no     ( hb_cs_n                  ),
    .hyper_ck_o      ( hb_ck                    ),
    .hyper_ck_no     ( hb_ck_n                  ),  // single-ended: no package pin
    .hyper_rwds_o    ( hb_rwds_o                ),
    .hyper_rwds_i    ( hb_rwds_i                ),
    .hyper_rwds_oe_o ( hb_rwds_oe               ),
    .hyper_dq_i      ( hb_dq_i                  ),
    .hyper_dq_o      ( hb_dq_o                  ),
    .hyper_dq_oe_o   ( hb_dq_oe                 ),
    .hyper_reset_no  ( hb_reset_n               )
);

// ============================================================
// Pad drive
// ============================================================

assign hb_dq_i   = pad_in_i[PadHbDqLsb +: 8];
assign hb_rwds_i = pad_in_i[PadHbRwds];

always_comb begin
    pad_out_o[NumMuxPads-1:0] = pm_pad_out;
    pad_oe_o [NumMuxPads-1:0] = pm_pad_oe;

    pad_out_o[PadHbDqLsb +: 8] = hb_dq_o;
    pad_oe_o [PadHbDqLsb +: 8] = {8{hb_dq_oe}};
    pad_out_o[PadHbRwds] = hb_rwds_o;
    pad_oe_o [PadHbRwds] = hb_rwds_oe;
    pad_out_o[PadHbCk]   = hb_ck;
    pad_oe_o [PadHbCk]   = 1'b1;
    pad_out_o[PadHbCsN]  = hb_cs_n;
    pad_oe_o [PadHbCsN]  = 1'b1;
    pad_out_o[PadHbRstN] = hb_reset_n;
    pad_oe_o [PadHbRstN] = 1'b1;
end

endmodule
