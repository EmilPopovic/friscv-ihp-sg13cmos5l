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

// Based on https://github.com/IHP-GmbH/ihp-sg13cmos5l-librelane-template/blob/main/src/chip_top.sv

`default_nettype none

`pragma diagnostic push
`pragma diagnostic ignore="-Wunused-def"
`pragma diagnostic ignore="-Wunconnected-inout-port"
module chip_top #(
    // Power/ground pads for core
    parameter int unsigned NUM_VDD_PADS = 6,
    parameter int unsigned NUM_VSS_PADS = 6,

    // Power/ground pads for I/O
    parameter int unsigned NUM_IOVDD_PADS = 5,
    parameter int unsigned NUM_IOVSS_PADS = 6,

    // Signal pads
    parameter int unsigned NUM_GPIO_PADS   = 10,
    parameter int unsigned NUM_QSPI_CS     = 3,
    parameter int unsigned NUM_HB_CS       = 2
) (
    `ifdef USE_POWER_PINS
    inout wire IOVDD,
    inout wire IOVSS,
    inout wire VDD,
    inout wire VSS,
    `endif
    inout wire clk_PAD,
    inout wire rst_n_PAD,
    inout wire clk_out_PAD,

    // JTAG
    inout wire jtag_tck_PAD,
    inout wire jtag_tms_PAD,
    inout wire jtag_tdi_PAD,
    inout wire jtag_trst_n_PAD,
    inout wire jtag_tdo_PAD,

    // UART0
    inout wire uart0_rx_PAD,
    inout wire uart0_tx_PAD,

    // GPIO Port A
    inout wire [NUM_GPIO_PADS-1:0] gpio_a_PAD,

    // QSPI0
    inout wire [3:0]             qspi0_io_PAD,
    inout wire                   qspi0_sck_PAD,
    inout wire [NUM_QSPI_CS-1:0] qspi0_cs_PAD,

    // HyperBus
    inout wire [7:0]           hb_dq_PAD,
    inout wire                 hb_rwds_PAD,
    inout wire                 hb_ck_PAD,
    inout wire [NUM_HB_CS-1:0] hb_cs_PAD,
    inout wire                 hb_rst_PAD
);

// Parameter checks
if (NUM_VDD_PADS < 1) begin : gen_chk_has_vdd
    $fatal(1, "chip_top: NUM_VDD_PADS must be >= 1, got %0d", NUM_VDD_PADS);
end
if (NUM_VSS_PADS < 1) begin : gen_chk_has_vss
    $fatal(1, "chip_top: NUM_VSS_PADS must be >= 1, got %0d", NUM_VSS_PADS);
end
if (NUM_IOVDD_PADS < 1) begin : gen_chk_has_iovdd
    $fatal(1, "chip_top: NUM_IOVDD_PADS must be >= 1, got %0d", NUM_IOVDD_PADS);
end
if (NUM_IOVSS_PADS < 1) begin : gen_chk_has_iovss
    $fatal(1, "chip_top: NUM_IOVSS_PADS must be >= 1, got %0d", NUM_IOVSS_PADS);
end
if (NUM_GPIO_PADS > 32) begin : gen_chk_max_gpio
    $fatal(1, "chip_top: NUM_GPIO_PADS must be <= 32, got %0d", NUM_GPIO_PADS);
end
if (NUM_QSPI_CS > 3) begin : gen_chk_legal_qspi_cs
    $fatal(1, "chip_top: NUM_QSPI_CS must be <= 3, got %0d", NUM_QSPI_CS);
end
if (NUM_HB_CS < 1 || NUM_HB_CS > 2) begin : gen_chk_legal_hb_cs
    $fatal(1, "chip_top: NUM_HB_CS must be 1 or 2, got %0d", NUM_HB_CS);
end

// ============================================================
// Clock and reset pad instances
// ============================================================

wire clk_PAD2CORE;
wire rst_n_PAD2CORE;

// Clock pad
(* keep *) sg13cmos5l_IOPadIn clk_pad (
    `ifdef USE_POWER_PINS
    .iovdd ( IOVDD ),
    .iovss ( IOVSS ),
    .vdd   ( VDD   ),
    .vss   ( VSS   ),
    `endif
    .p2c   ( clk_PAD2CORE ),
    .pad   ( clk_PAD      )
);

// Reset pad
(* keep *) sg13cmos5l_IOPadIn rst_n_pad (
    `ifdef USE_POWER_PINS
    .iovdd ( IOVDD ),
    .iovss ( IOVSS ),
    .vdd   ( VDD   ),
    .vss   ( VSS   ),
    `endif
    .p2c   ( rst_n_PAD2CORE ),
    .pad   ( rst_n_PAD      )
);

// ============================================================
// Power/ground pad instances
// ============================================================

// IOVDD pads
for (genvar i = 0; i < NUM_IOVDD_PADS; i++) begin : iovdd_pads
    (* keep *) sg13cmos5l_IOPadIOVdd iovdd_pad (
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
    (* keep *) sg13cmos5l_IOPadIOVss iovss_pad (
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
    (* keep *) sg13cmos5l_IOPadVdd vdd_pad (
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
    (* keep *) sg13cmos5l_IOPadVss vss_pad (
        `ifdef USE_POWER_PINS
        .iovdd ( IOVDD ),
        .iovss ( IOVSS ),
        .vdd   ( VDD   ),
        .vss   ( VSS   )
        `endif
    );
end

// ============================================================
// JTAG pad instances
// ============================================================

wire jtag_tck_PAD2CORE;
wire jtag_tms_PAD2CORE;
wire jtag_tdi_PAD2CORE;
wire jtag_trst_n_PAD2CORE;
wire jtag_tdo_CORE2PAD;

// TCK pad
(* keep *) sg13cmos5l_IOPadIn jtag_tck_pad (
    `ifdef USE_POWER_PINS
    .iovdd ( IOVDD ),
    .iovss ( IOVSS ),
    .vdd   ( VDD   ),
    .vss   ( VSS   ),
    `endif
    .p2c   ( jtag_tck_PAD2CORE ),
    .pad   ( jtag_tck_PAD      )
);

// TMS pad
(* keep *) sg13cmos5l_IOPadIn jtag_tms_pad (
    `ifdef USE_POWER_PINS
    .iovdd ( IOVDD ),
    .iovss ( IOVSS ),
    .vdd   ( VDD   ),
    .vss   ( VSS   ),
    `endif
    .p2c   ( jtag_tms_PAD2CORE ),
    .pad   ( jtag_tms_PAD      )
);

// TDI pad
(* keep *) sg13cmos5l_IOPadIn jtag_tdi_pad (
    `ifdef USE_POWER_PINS
    .iovdd ( IOVDD ),
    .iovss ( IOVSS ),
    .vdd   ( VDD   ),
    .vss   ( VSS   ),
    `endif
    .p2c   ( jtag_tdi_PAD2CORE ),
    .pad   ( jtag_tdi_PAD      )
);

// TRST# pad
(* keep *) sg13cmos5l_IOPadIn jtag_trst_n_pad (
    `ifdef USE_POWER_PINS
    .iovdd ( IOVDD ),
    .iovss ( IOVSS ),
    .vdd   ( VDD   ),
    .vss   ( VSS   ),
    `endif
    .p2c   ( jtag_trst_n_PAD2CORE ),
    .pad   ( jtag_trst_n_PAD      )
);

// TDO pad
(* keep *) sg13cmos5l_IOPadOut30mA jtag_tdo_pad (
    `ifdef USE_POWER_PINS
    .iovdd ( IOVDD ),
    .iovss ( IOVSS ),
    .vdd   ( VDD   ),
    .vss   ( VSS   ),
    `endif
    .c2p   ( jtag_tdo_CORE2PAD ),
    .pad   ( jtag_tdo_PAD      )
);

// ============================================================
// UART0 pad instances
// ============================================================

wire uart0_rx_PAD2CORE;
wire uart0_tx_CORE2PAD;

// RX pad
(* keep *) sg13cmos5l_IOPadIn uart0_rx_pad (
    `ifdef USE_POWER_PINS
    .iovdd ( IOVDD ),
    .iovss ( IOVSS ),
    .vdd   ( VDD   ),
    .vss   ( VSS   ),
    `endif
    .p2c   ( uart0_rx_PAD2CORE ),
    .pad   ( uart0_rx_PAD      )
);

// TX pad
(* keep *) sg13cmos5l_IOPadOut30mA uart0_tx_pad (
    `ifdef USE_POWER_PINS
    .iovdd ( IOVDD ),
    .iovss ( IOVSS ),
    .vdd   ( VDD   ),
    .vss   ( VSS   ),
    `endif
    .c2p   ( uart0_tx_CORE2PAD ),
    .pad   ( uart0_tx_PAD      )
);

wire clk_out_CORE2PAD;

// Output clock pad
(* keep *) sg13cmos5l_IOPadOut30mA clk_out_pad (
    `ifdef USE_POWER_PINS
    .iovdd ( IOVDD ),
    .iovss ( IOVSS ),
    .vdd   ( VDD   ),
    .vss   ( VSS   ),
    `endif
    .c2p   ( clk_out_CORE2PAD ),
    .pad   ( clk_out_PAD      )
);

// ============================================================
// GPIO pad instances
// ============================================================

wire [NUM_GPIO_PADS-1:0] gpio_a_PAD2CORE;
wire [NUM_GPIO_PADS-1:0] gpio_a_CORE2PAD;
wire [NUM_GPIO_PADS-1:0] gpio_a_CORE2PAD_OE;

for (genvar i = 0; i < NUM_GPIO_PADS; i++) begin : gpio_a_pads
    (* keep *) sg13cmos5l_IOPadInOut30mA gpio_a_pad (
        `ifdef USE_POWER_PINS
        .iovdd  ( IOVDD ),
        .iovss  ( IOVSS ),
        .vdd    ( VDD   ),
        .vss    ( VSS   ),
        `endif
        .c2p    ( gpio_a_CORE2PAD[i]    ),
        .c2p_en ( gpio_a_CORE2PAD_OE[i] ),
        .p2c    ( gpio_a_PAD2CORE[i]    ),
        .pad    ( gpio_a_PAD[i]         )
    );
end

// ============================================================
// QSPI0 pad instances
// ============================================================

wire [3:0]             qspi0_io_PAD2CORE;
wire [3:0]             qspi0_io_CORE2PAD;
wire [3:0]             qspi0_io_CORE2PAD_OE;
wire                   qspi0_sck_CORE2PAD;
wire [NUM_QSPI_CS-1:0] qspi0_cs_CORE2PAD;

// QSPI0 I/O pads
for (genvar i = 0; i < 4; i++) begin : qspi0_io_pads
    (* keep *) sg13cmos5l_IOPadInOut30mA qspi0_io_pad (
        `ifdef USE_POWER_PINS
        .iovdd  ( IOVDD ),
        .iovss  ( IOVSS ),
        .vdd    ( VDD   ),
        .vss    ( VSS   ),
        `endif
        .c2p    ( qspi0_io_CORE2PAD[i]    ),
        .c2p_en ( qspi0_io_CORE2PAD_OE[i] ),
        .p2c    ( qspi0_io_PAD2CORE[i]    ),
        .pad    ( qspi0_io_PAD[i]         )
    );
end

// QSPI0 CS# pads
for (genvar i = 0; i < NUM_QSPI_CS; i++) begin : qspi0_cs_pads
    (* keep *) sg13cmos5l_IOPadOut30mA qspi0_cs_pad (
        `ifdef USE_POWER_PINS
        .iovdd  ( IOVDD ),
        .iovss  ( IOVSS ),
        .vdd    ( VDD   ),
        .vss    ( VSS   ),
        `endif
        .c2p    ( qspi0_cs_CORE2PAD[i] ),
        .pad    ( qspi0_cs_PAD[i]      )
    );
end

// QSPI0 SCK pad
(* keep *) sg13cmos5l_IOPadOut30mA qspi0_sck_pad (
    `ifdef USE_POWER_PINS
    .iovdd  ( IOVDD ),
    .iovss  ( IOVSS ),
    .vdd    ( VDD   ),
    .vss    ( VSS   ),
    `endif
    .c2p    ( qspi0_sck_CORE2PAD ),
    .pad    ( qspi0_sck_PAD      )
);

// ============================================================
// HyperBus pad instances
// ============================================================

wire [7:0]           hb_dq_PAD2CORE;
wire [7:0]           hb_dq_CORE2PAD;
wire                 hb_dq_CORE2PAD_OE;
wire                 hb_rwds_PAD2CORE;
wire                 hb_rwds_CORE2PAD;
wire                 hb_rwds_CORE2PAD_OE;
wire                 hb_ck_CORE2PAD;
wire [NUM_HB_CS-1:0] hb_cs_CORE2PAD;
wire                 hb_rst_CORE2PAD;

// HyperBus DQ pads
for (genvar i = 0; i < 8; i++) begin : hb_dq_pads
    (* keep *) sg13cmos5l_IOPadInOut30mA hb_dq_pad (
        `ifdef USE_POWER_PINS
        .iovdd  ( IOVDD ),
        .iovss  ( IOVSS ),
        .vdd    ( VDD   ),
        .vss    ( VSS   ),
        `endif
        .c2p    ( hb_dq_CORE2PAD[i]  ),
        .c2p_en ( hb_dq_CORE2PAD_OE  ),
        .p2c    ( hb_dq_PAD2CORE[i]  ),
        .pad    ( hb_dq_PAD[i]       )
    );
end

// HyperBus CS# pads
for (genvar i = 0; i < NUM_HB_CS; i++) begin : hb_cs_pads
    (* keep *) sg13cmos5l_IOPadOut30mA hb_cs_pad (
        `ifdef USE_POWER_PINS
        .iovdd  ( IOVDD ),
        .iovss  ( IOVSS ),
        .vdd    ( VDD   ),
        .vss    ( VSS   ),
        `endif
        .c2p    ( hb_cs_CORE2PAD[i] ),
        .pad    ( hb_cs_PAD[i]      )
    );
end

// HyperBus RWDS pad
(* keep *) sg13cmos5l_IOPadInOut30mA hb_rwds_pad (
    `ifdef USE_POWER_PINS
    .iovdd  ( IOVDD ),
    .iovss  ( IOVSS ),
    .vdd    ( VDD   ),
    .vss    ( VSS   ),
    `endif
    .c2p    ( hb_rwds_CORE2PAD    ),
    .c2p_en ( hb_rwds_CORE2PAD_OE ),
    .p2c    ( hb_rwds_PAD2CORE    ),
    .pad    ( hb_rwds_PAD         )
);

// HyperBus CK pad
(* keep *) sg13cmos5l_IOPadOut30mA hb_ck_pad (
    `ifdef USE_POWER_PINS
    .iovdd  ( IOVDD ),
    .iovss  ( IOVSS ),
    .vdd    ( VDD   ),
    .vss    ( VSS   ),
    `endif
    .c2p    ( hb_ck_CORE2PAD ),
    .pad    ( hb_ck_PAD      )
);

// HyperBus RST# pad
(* keep *) sg13cmos5l_IOPadOut30mA hb_rst_pad (
    `ifdef USE_POWER_PINS
    .iovdd  ( IOVDD ),
    .iovss  ( IOVSS ),
    .vdd    ( VDD   ),
    .vss    ( VSS   ),
    `endif
    .c2p    ( hb_rst_CORE2PAD ),
    .pad    ( hb_rst_PAD      )
);

// ============================================================
// Core
// ============================================================

`pragma diagnostic push
`pragma diagnostic ignore="-Wempty-output-connection"
(* keep *) friscv_chip_soc #(
    .NumGpios ( NUM_GPIO_PADS ),
    .MemChips ( NUM_HB_CS     )
) soc_inst (
    .clk_i           ( clk_PAD2CORE         ),
    .rst_ni          ( rst_n_PAD2CORE       ),
    .clk_out_o       ( clk_out_CORE2PAD     ),
    .end_o           ( /* no package pin */ ),

    // JTAG
    .jtag_tck_i      ( jtag_tck_PAD2CORE    ),
    .jtag_tms_i      ( jtag_tms_PAD2CORE    ),
    .jtag_trst_ni    ( jtag_trst_n_PAD2CORE ),
    .jtag_tdi_i      ( jtag_tdi_PAD2CORE    ),
    .jtag_tdo_o      ( jtag_tdo_CORE2PAD    ),
    .jtag_tdo_oe_o   ( /* no package pin */ ),

    // UART0
    .uart0_rx_i      ( uart0_rx_PAD2CORE    ),
    .uart0_tx_o      ( uart0_tx_CORE2PAD    ),

    // QSPI0
    .qspi0_sck_o     ( qspi0_sck_CORE2PAD   ),
    .qspi0_cs_o      ( qspi0_cs_CORE2PAD    ),
    .qspi0_sd_i      ( qspi0_io_PAD2CORE    ),
    .qspi0_sd_o      ( qspi0_io_CORE2PAD    ),
    .qspi0_sd_oe_o   ( qspi0_io_CORE2PAD_OE ),

    // HyperBus
    .hyper_dq_i      ( hb_dq_PAD2CORE       ),
    .hyper_dq_o      ( hb_dq_CORE2PAD       ),
    .hyper_dq_oe_o   ( hb_dq_CORE2PAD_OE    ),
    .hyper_rwds_i    ( hb_rwds_PAD2CORE     ),
    .hyper_rwds_o    ( hb_rwds_CORE2PAD     ),
    .hyper_rwds_oe_o ( hb_rwds_CORE2PAD_OE  ),
    .hyper_ck_o      ( hb_ck_CORE2PAD       ),
    .hyper_cs_no     ( hb_cs_CORE2PAD       ),
    .hyper_reset_no  ( hb_rst_CORE2PAD      ),

    // GPIO Port A
    .gpio_a_i        ( gpio_a_PAD2CORE      ),
    .gpio_a_o        ( gpio_a_CORE2PAD      ),
    .gpio_a_oe_o     ( gpio_a_CORE2PAD_OE   )
);
`pragma diagnostic pop

endmodule
`pragma diagnostic pop

`default_nettype wire
