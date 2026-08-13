// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Emil Popović <mail@emilpopovic.me>
// Matej Jurasić <matej.jurasic@cappig.dev>

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
    input  logic  clk_i,
    input  logic  rst_ni,

    output logic  clk_out_o,

    output logic  end_o,

    // UART0
    input  logic  uart0_rx_i,
    output logic  uart0_tx_o,

    // JTAG
    input  logic  jtag_tck_i,
    input  logic  jtag_tms_i,
    input  logic  jtag_trst_ni,
    input  logic  jtag_tdi_i,
    output logic  jtag_tdo_o,
    output logic  jtag_tdo_oe_o,

    // QSPI0; SCK and the chip selects are always driven
    output logic       qspi0_sck_o,
    output logic [2:0] qspi0_cs_o,
    input  logic [3:0] qspi0_sd_i,
    output logic [3:0] qspi0_sd_o,
    output logic [3:0] qspi0_sd_oe_o,

    // HyperBus
    input  logic [7:0]          hyper_dq_i,
    output logic [7:0]          hyper_dq_o,
    output logic                hyper_dq_oe_o,
    input  logic                hyper_rwds_i,
    output logic                hyper_rwds_o,
    output logic                hyper_rwds_oe_o,
    output logic                hyper_ck_o,
    output logic [MemChips-1:0] hyper_cs_no,
    output logic                hyper_reset_no,

    // GPIO Port A, PA0..PA(NumGpios-1); also the reset straps
    input  logic [NumGpios-1:0] gpio_a_i,
    output logic [NumGpios-1:0] gpio_a_o,
    output logic [NumGpios-1:0] gpio_a_oe_o
);

// Output clock as heartbeat, do not use as real clock
logic [6:0] clk_div;
always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) clk_div <= '0;
    else         clk_div <= clk_div + 1;
end
assign clk_out_o = clk_div[6];

localparam int unsigned HyperCfgSlv  = 0;
localparam int unsigned NumExtRegSlv = 1;

localparam logic [31:0] HyperCfgBaseAddr = 32'h5001_0000;
localparam logic [31:0] HyperCfgSize     = 32'h0000_1000;

localparam axi_pkg::xbar_rule_32_t [NumExtRegSlv-1:0] ExtRegSlvRules = '{
    '{ idx: HyperCfgSlv, start_addr: HyperCfgBaseAddr, end_addr: HyperCfgBaseAddr + HyperCfgSize }
};

logic soc_rstn;

vernii_axi_req_t  axi_mem_req;
vernii_axi_resp_t axi_mem_rsp;

vernii_reg_req_t [NumExtRegSlv-1:0] reg_ext_req;
vernii_reg_rsp_t [NumExtRegSlv-1:0] reg_ext_rsp;

logic [31:0] gpio_a_in, gpio_a_out, gpio_a_oe;

assign gpio_a_in      = 32'(gpio_a_i);
assign gpio_a_o     = gpio_a_out[NumGpios-1:0];
assign gpio_a_oe_o  = gpio_a_oe [NumGpios-1:0];

vernii_soc #(
    .OcmBase          ( SramBase           ),
    .OcmSize          ( SramSize           ),
    .ExtBase          ( MemBase            ),
    .ExtSize          ( MemSize * MemChips ),
    .LineBytes        ( LineBytes          ),
    .Ways             ( Ways               ),
    .SramTags         ( SramTags           ),
    .ZsblRomSizeBytes ( ZsblRomSizeBytes   ),
    .NumStraps        ( NumGpios           ),
    .NumExtRegSlv     ( NumExtRegSlv       ),
    .ExtRegSlvRules   ( ExtRegSlvRules     )
) i_vernii_soc (
    .clk_i,
    .rst_ni,
    .por_rst_no     ( /* unused */ ),
    .soc_rst_no     ( soc_rstn     ),
    .end_o,
    .axi_mem_req_o  ( axi_mem_req  ),
    .axi_mem_rsp_i  ( axi_mem_rsp  ),
    .reg_ext_req_o  ( reg_ext_req  ),
    .reg_ext_rsp_i  ( reg_ext_rsp  ),
    .strap_i        ( gpio_a_i     ),
    .uart0_rx_i,
    .uart0_tx_o,
    .jtag_tck_i,
    .jtag_tms_i,
    .jtag_trst_ni,
    .jtag_tdi_i,
    .jtag_tdo_o,
    .jtag_tdo_oe_o,
    .qspi0_sck_o,
    .qspi0_sck_oe_o ( /* no package pin */ ),  // tied high inside spi_host
    .qspi0_cs_o,
    .qspi0_cs_oe_o  ( /* no package pin */ ),  // tied high inside spi_host
    .qspi0_sd_o,
    .qspi0_sd_oe_o,
    .qspi0_sd_i,
    .ext_irq_i      ( '0           ),
    .gpio_a_i       ( gpio_a_in    ),
    .gpio_a_o       ( gpio_a_out   ),
    .gpio_a_oe_o    ( gpio_a_oe    )
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

`pragma diagnostic push
`pragma diagnostic ignore="-Wempty-output-connection"
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
    .clk_phy_i       ( clk_i                    ),
    .rst_phy_ni      ( soc_rstn                 ),
    .clk_sys_i       ( clk_i                    ),
    .rst_sys_ni      ( soc_rstn                 ),
    .test_mode_i     ( 1'b0                     ),
    .axi_req_i       ( axi_mem_req              ),
    .axi_rsp_o       ( axi_mem_rsp              ),
    .reg_req_i       ( reg_ext_req[HyperCfgSlv] ),
    .reg_rsp_o       ( reg_ext_rsp[HyperCfgSlv] ),
    .hyper_cs_no,
    .hyper_ck_o,
    .hyper_ck_no     ( /* no package pin */     ),  // single-ended
    .hyper_rwds_o,
    .hyper_rwds_i,
    .hyper_rwds_oe_o,
    .hyper_dq_i,
    .hyper_dq_o,
    .hyper_dq_oe_o,
    .hyper_reset_no
);
`pragma diagnostic pop

endmodule
