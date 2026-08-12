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
    // Window of one HyperBus device, SoC sees MemChips of them back to back
    parameter int unsigned MemSize           = 32'h0100_0000,
    parameter int unsigned MemChips          = 2,
    parameter int unsigned LineBytes         = 32,
    parameter int unsigned Ways              = 4,
    parameter bit          SramTags          = 1'b1,
    parameter bit          HyperClockDelayed = 1'b1,
    parameter int unsigned NumGpios          = 10,
    parameter int unsigned ZsblRomSizeBytes  = 128
) (
    input  logic  i_clk,
    input  logic  i_rstn,

    output logic  o_clk_out,

    output logic  o_end,

    // UART0
    input  logic  i_uart_rx,
    output logic  o_uart_tx,

    // JTAG
    input  logic  i_jtag_tck,
    input  logic  i_jtag_tms,
    input  logic  i_jtag_trstn,
    input  logic  i_jtag_tdi,
    output logic  o_jtag_tdo,
    output logic  o_jtag_tdo_oe,

    // QSPI0; SCK and the chip selects are always driven
    output logic       o_qspi_sck,
    output logic [2:0] o_qspi_csn,
    input  logic [3:0] i_qspi_sd,
    output logic [3:0] o_qspi_sd,
    output logic [3:0] o_qspi_sd_oe,

    // HyperBus
    input  logic [7:0]          i_hyper_dq,
    output logic [7:0]          o_hyper_dq,
    output logic                o_hyper_dq_oe,
    input  logic                i_hyper_rwds,
    output logic                o_hyper_rwds,
    output logic                o_hyper_rwds_oe,
    output logic                o_hyper_ck,
    output logic [MemChips-1:0] o_hyper_csn,
    output logic                o_hyper_rstn,

    // GPIO Port A, PA0..PA(NumGpios-1); also the reset straps
    input  logic [NumGpios-1:0] i_gpio,
    output logic [NumGpios-1:0] o_gpio,
    output logic [NumGpios-1:0] o_gpio_oe
);

// Output clock as heartbeat, do not use as real clock
logic [6:0] clk_div;
always_ff @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) clk_div <= '0;
    else         clk_div <= clk_div + 1;
end
assign o_clk_out = clk_div[6];

localparam int unsigned HyperCfgSlv  = 0;
localparam int unsigned NumExtRegSlv = 1;

localparam logic [31:0] HyperCfgBaseAddr = 32'h5001_0000;
localparam logic [31:0] HyperCfgSize     = 32'h0000_1000;

localparam axi_pkg::xbar_rule_32_t [NumExtRegSlv-1:0] ExtRegSlvRules = '{
    '{ idx: HyperCfgSlv, start_addr: HyperCfgBaseAddr, end_addr: HyperCfgBaseAddr + HyperCfgSize }
};

logic por_rstn, soc_rstn;

vernii_axi_req_t  axi_mem_req;
vernii_axi_resp_t axi_mem_rsp;

vernii_reg_req_t [NumExtRegSlv-1:0] reg_ext_req;
vernii_reg_rsp_t [NumExtRegSlv-1:0] reg_ext_rsp;

logic [31:0] gpio_in, gpio_out, gpio_oe;

assign gpio_in    = 32'(i_gpio);
assign o_gpio     = gpio_out[NumGpios-1:0];
assign o_gpio_oe  = gpio_oe [NumGpios-1:0];

vernii_soc #(
    .SramBase         ( SramBase           ),
    .SramSize         ( SramSize           ),
    .MemBase          ( MemBase            ),
    .MemSize          ( MemSize * MemChips ),
    .LineBytes        ( LineBytes          ),
    .Ways             ( Ways               ),
    .SramTags         ( SramTags           ),
    .ZsblRomSizeBytes ( ZsblRomSizeBytes   ),
    .NumStraps        ( NumGpios           ),
    .NumExtRegSlv     ( NumExtRegSlv       ),
    .ExtRegSlvRules   ( ExtRegSlvRules     )
) i_vernii_soc (
    .i_clk         ( i_clk         ),
    .i_rstn        ( i_rstn        ),
    .o_por_rstn    ( por_rstn      ),
    .o_soc_rstn    ( soc_rstn      ),
    .o_end         ( o_end         ),
    .o_axi_mem_req ( axi_mem_req   ),
    .i_axi_mem_rsp ( axi_mem_rsp   ),
    .o_reg_ext_req ( reg_ext_req   ),
    .i_reg_ext_rsp ( reg_ext_rsp   ),
    .i_strap       ( i_gpio        ),
    .i_uart_rx     ( i_uart_rx     ),
    .o_uart_tx     ( o_uart_tx     ),
    .i_jtag_tck    ( i_jtag_tck    ),
    .i_jtag_tms    ( i_jtag_tms    ),
    .i_jtag_trstn  ( i_jtag_trstn  ),
    .i_jtag_tdi    ( i_jtag_tdi    ),
    .o_jtag_tdo    ( o_jtag_tdo    ),
    .o_jtag_tdo_oe ( o_jtag_tdo_oe ),
    .o_qspi_sck    ( o_qspi_sck    ),
    .o_qspi_sck_oe (               ),  // tied high inside spi_host
    .o_qspi_cs     ( o_qspi_csn    ),
    .o_qspi_cs_oe  (               ),  // tied high inside spi_host
    .o_qspi_sd     ( o_qspi_sd     ),
    .o_qspi_sd_oe  ( o_qspi_sd_oe  ),
    .i_qspi_sd     ( i_qspi_sd     ),
    .i_ext_irq     ( '0            ),
    .i_gpio        ( gpio_in       ),
    .o_gpio        ( gpio_out      ),
    .o_gpio_oe     ( gpio_oe       )
);

// ============================================================
// External memory
// ============================================================

localparam int unsigned HyperNumPhys    = 1;
localparam int unsigned HyperMinFreqMHz = 40;

// Requests past the mask alias onto low addresses instead of faulting
function automatic hyperbus_pkg::hyper_cfg_t hyper_rst_cfg();
    hyper_rst_cfg = hyperbus_pkg::gen_RstCfg(HyperNumPhys, HyperMinFreqMHz);
    hyper_rst_cfg.address_mask_msb = 5'($clog2(MemSize));
endfunction

hyperbus #(
    .NumChips        ( MemChips                ),
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
    .hyper_cs_no     ( o_hyper_csn              ),
    .hyper_ck_o      ( o_hyper_ck               ),
    .hyper_ck_no     (                          ),  // single-ended: no package pin
    .hyper_rwds_o    ( o_hyper_rwds             ),
    .hyper_rwds_i    ( i_hyper_rwds             ),
    .hyper_rwds_oe_o ( o_hyper_rwds_oe          ),
    .hyper_dq_i      ( i_hyper_dq               ),
    .hyper_dq_o      ( o_hyper_dq               ),
    .hyper_dq_oe_o   ( o_hyper_dq_oe            ),
    .hyper_reset_no  ( o_hyper_rstn             )
);

endmodule
