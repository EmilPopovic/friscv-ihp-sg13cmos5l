// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/

`default_nettype none

module friscv_soc_pynq #(
    parameter int unsigned SramCfg  = 1,  // 0 = tapeout map, 1 = riscv-arch-test map
    parameter int unsigned ZsblRom  = 1,  // 0 removes the boot ROM, for CONFIG=preload
    parameter int unsigned NumGpios = 10,
    parameter int unsigned NumHbCs  = 2
) (
    input  wire                clk_125_i,   // H16, 125 MHz board oscillator
    input  wire                btn_rst_i,   // BTN0, active high

    output wire [3:0]          led_o,       // LD0..LD3

    // JTAG
    input  wire                jtag_tck_i,
    input  wire                jtag_tms_i,
    input  wire                jtag_tdi_i,
    output wire                jtag_tdo_o,

    // UART0
    input  wire                uart_rx_i,
    output wire                uart_tx_o,

    output wire                clk_out_o,

    // GPIO Port A, PA0..PA9
    inout  wire [NumGpios-1:0] gpio_io,

    // QSPI0
    inout  wire [3:0]          qspi_io,
    output wire                qspi_sck_o,
    output wire [2:0]          qspi_cs_o,

    // HyperBus
    inout  wire [7:0]          hb_dq_io,
    inout  wire                hb_rwds_io,
    output wire                hb_ck_o,
    output wire [NumHbCs-1:0]  hb_cs_o,
    output wire                hb_rst_o
);

localparam int unsigned SramBase = (SramCfg == 0) ? 32'h0000_0000 : 32'h8000_0000;
localparam int unsigned SramSize = (SramCfg == 0) ? 32'h0000_4000 : 32'h0008_0000;

// friscv_soc defaults, the external HyperBus window
localparam int unsigned MemBase = 32'h8000_0000;
localparam int unsigned MemSize = 32'h0100_0000;

// 25 MHz, not the ASIC's 50 MHz: the 512 KiB SRAM spans 128 cascaded block RAMs
// and misses a 20 ns period by 5.5 ns. Software has to program the CLINT tick
// generator for whatever these dividers end up producing.
localparam real ClkInPeriodNs = 8.000;   // 125 MHz board clock
localparam real MmcmMultF     = 8.000;   // VCO = 1000 MHz
localparam int  MmcmDivClk    = 1;
localparam real SocClkDivideF = 40.000;  // 25 MHz

wire mmcm_clk_fb;
wire mmcm_clk_soc;
wire mmcm_locked;
wire soc_clk;

MMCME2_BASE #(
    .BANDWIDTH        ( "OPTIMIZED"   ),
    .CLKIN1_PERIOD    ( ClkInPeriodNs ),
    .DIVCLK_DIVIDE    ( MmcmDivClk    ),
    .CLKFBOUT_MULT_F  ( MmcmMultF     ),
    .CLKOUT0_DIVIDE_F ( SocClkDivideF ),
    .STARTUP_WAIT     ( "FALSE"       )
) i_mmcm (
    .CLKIN1    ( clk_125_i    ),
    .CLKFBIN   ( mmcm_clk_fb  ),
    .CLKFBOUT  ( mmcm_clk_fb  ),
    .CLKOUT0   ( mmcm_clk_soc ),
    .LOCKED    ( mmcm_locked  ),
    .PWRDWN    ( 1'b0         ),
    .RST       ( 1'b0         )
);

BUFG i_bufg_soc (
    .I ( mmcm_clk_soc ),
    .O ( soc_clk      )
);

// Async assert, sync release 1024 cycles later
localparam int unsigned RstCntW = 10;

wire arst_n;
assign arst_n = mmcm_locked & ~btn_rst_i;

logic [RstCntW-1:0] rst_cnt;
logic               soc_rstn;

always_ff @(posedge soc_clk or negedge arst_n) begin
    if (!arst_n) begin
        rst_cnt  <= '0;
        soc_rstn <= 1'b0;
    end else if (rst_cnt != {RstCntW{1'b1}}) begin
        rst_cnt  <= rst_cnt + 1'b1;
        soc_rstn <= 1'b0;
    end else begin
        soc_rstn <= 1'b1;
    end
end

// Not reset, so a blinking LD3 separates a stopped clock from a held reset
logic [23:0] heartbeat_cnt;
always_ff @(posedge soc_clk) begin
    heartbeat_cnt <= heartbeat_cnt + 1'b1;
end

wire soc_end;

assign led_o[0] = soc_end;            // wrote to END_ADDRESS
assign led_o[1] = mmcm_locked;
assign led_o[2] = ~soc_rstn;
assign led_o[3] = heartbeat_cnt[23];  // ~1.5 Hz

wire [NumGpios-1:0] gpio_in, gpio_out, gpio_oe;
wire [3:0]          qspi_sd_in, qspi_sd_out, qspi_sd_oe;
wire [7:0]          hb_dq_in, hb_dq_out;
wire                hb_dq_oe;
wire                hb_rwds_in, hb_rwds_out, hb_rwds_oe;

// Bidirectional pads
for (genvar i = 0; i < NumGpios; i++) begin : gen_gpio_pads
    IOBUF i_iobuf (
        .O  (  gpio_in [i] ),
        .IO (  gpio_io [i] ),
        .I  (  gpio_out[i] ),
        .T  ( ~gpio_oe [i] )
    );
end

for (genvar i = 0; i < 4; i++) begin : gen_qspi_io_pads
    IOBUF i_iobuf (
        .O  (  qspi_sd_in [i] ),
        .IO (  qspi_io    [i] ),
        .I  (  qspi_sd_out[i] ),
        .T  ( ~qspi_sd_oe [i] )
    );
end

for (genvar i = 0; i < 8; i++) begin : gen_hb_dq_pads
    IOBUF i_iobuf (
        .O  (  hb_dq_in [i] ),
        .IO (  hb_dq_io [i] ),
        .I  (  hb_dq_out[i] ),
        .T  ( ~hb_dq_oe     )
    );
end

IOBUF i_hb_rwds_iobuf (
    .O  (  hb_rwds_in  ),
    .IO (  hb_rwds_io  ),
    .I  (  hb_rwds_out ),
    .T  ( ~hb_rwds_oe  )
);

// Core design
friscv_chip_soc #(
    .SramBase          ( SramBase                         ),
    .SramSize          ( SramSize                         ),
    .MemBase           ( MemBase                          ),
    .MemSize           ( MemSize                          ),
    .MemChips          ( NumHbCs                          ),
    // configurable_delay is a zero-delay stub here, as in the SoC testbench
    .HyperClockDelayed ( 1'b0                             ),
    .NumGpios          ( NumGpios                         ),
    .ZsblRomSizeBytes  ( (ZsblRom != 0) ? 32'd144 : 32'd0 )
) i_friscv_soc (
    .i_clk           ( soc_clk     ),
    .i_rstn          ( soc_rstn    ),

    .o_clk_out       ( clk_out_o   ),
    .o_end           ( soc_end     ),

    .i_uart_rx       ( uart_rx_i   ),
    .o_uart_tx       ( uart_tx_o   ),

    .i_jtag_tck      ( jtag_tck_i  ),
    .i_jtag_tms      ( jtag_tms_i  ),
    .i_jtag_trstn    ( 1'b1        ),
    .i_jtag_tdi      ( jtag_tdi_i  ),
    .o_jtag_tdo      ( jtag_tdo_o  ),
    .o_jtag_tdo_oe   (             ),

    .o_qspi_sck      ( qspi_sck_o  ),
    .o_qspi_csn      ( qspi_cs_o   ),
    .i_qspi_sd       ( qspi_sd_in  ),
    .o_qspi_sd       ( qspi_sd_out ),
    .o_qspi_sd_oe    ( qspi_sd_oe  ),

    .i_hyper_dq      ( hb_dq_in    ),
    .o_hyper_dq      ( hb_dq_out   ),
    .o_hyper_dq_oe   ( hb_dq_oe    ),
    .i_hyper_rwds    ( hb_rwds_in  ),
    .o_hyper_rwds    ( hb_rwds_out ),
    .o_hyper_rwds_oe ( hb_rwds_oe  ),
    .o_hyper_ck      ( hb_ck_o     ),
    .o_hyper_csn     ( hb_cs_o     ),
    .o_hyper_rstn    ( hb_rst_o    ),

    .i_gpio          ( gpio_in     ),
    .o_gpio          ( gpio_out    ),
    .o_gpio_oe       ( gpio_oe     )
);

endmodule

`default_nettype wire
