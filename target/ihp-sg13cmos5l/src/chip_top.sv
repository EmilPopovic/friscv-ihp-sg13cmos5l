// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/

// Based on https://github.com/IHP-GmbH/ihp-sg13cmos5l-librelane-template/blob/main/src/chip_top.sv

`default_nettype none

module chip_top #(
    // Power/ground pads for core
    parameter NUM_VDD_PADS = 6,
    parameter NUM_VSS_PADS = 6,

    // Power/ground pads for I/O
    parameter NUM_IOVDD_PADS = 5,
    parameter NUM_IOVSS_PADS = 6,

    // Signal pads
    parameter NUM_GPIO_PADS   = 10,
    parameter NUM_QSPI_CS     = 3,
    parameter NUM_HB_CS       = 2
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
    inout wire uart_rx_PAD,
    inout wire uart_tx_PAD,

    // GPIO Port A
    inout wire [NUM_GPIO_PADS-1:0] gpio_PAD,

    // QSPI0
    inout wire [3:0]             qspi_io_PAD,
    inout wire                   qspi_sck_PAD,
    inout wire [NUM_QSPI_CS-1:0] qspi_cs_PAD,

    // HyperBus
    inout wire [7:0]           hb_dq_PAD,
    inout wire                 hb_rwds_PAD,
    inout wire                 hb_ck_PAD,
    inout wire [NUM_HB_CS-1:0] hb_cs_PAD,
    inout wire                 hb_rst_PAD
);

// ============================================================
// Clock and reset pad instances
// ============================================================

wire clk_PAD2CORE;
wire rst_n_PAD2CORE;

// Clock pad
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

// Reset pad
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

// ============================================================
// Power/ground pad instances
// ============================================================

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

// ============================================================
// JTAG pad instances
// ============================================================

wire jtag_tck_PAD2CORE;
wire jtag_tms_PAD2CORE;
wire jtag_tdi_PAD2CORE;
wire jtag_trst_n_PAD2CORE;
wire jtag_tdo_CORE2PAD;

// TCK pad
sg13cmos5l_IOPadIn jtag_tck_pad (
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
sg13cmos5l_IOPadIn jtag_tms_pad (
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
sg13cmos5l_IOPadIn jtag_tdi_pad (
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
sg13cmos5l_IOPadIn jtag_trst_n_pad (
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
sg13cmos5l_IOPadOut30mA jtag_tdo_pad (
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

wire uart_rx_PAD2CORE;
wire uart_tx_CORE2PAD;

// RX pad
sg13cmos5l_IOPadIn uart_rx_pad (
    `ifdef USE_POWER_PINS
    .iovdd ( IOVDD ),
    .iovss ( IOVSS ),
    .vdd   ( VDD   ),
    .vss   ( VSS   ),
    `endif
    .p2c   ( uart_rx_PAD2CORE ),
    .pad   ( uart_rx_PAD      )
);

// TX pad
sg13cmos5l_IOPadOut30mA uart_tx_pad (
    `ifdef USE_POWER_PINS
    .iovdd ( IOVDD ),
    .iovss ( IOVSS ),
    .vdd   ( VDD   ),
    .vss   ( VSS   ),
    `endif
    .c2p   ( uart_tx_CORE2PAD ),
    .pad   ( uart_tx_PAD      )
);

wire clk_out_CORE2PAD;

// Output clock pad
sg13cmos5l_IOPadOut30mA clk_out_pad (
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

wire [NUM_GPIO_PADS-1:0] gpio_PAD2CORE;
wire [NUM_GPIO_PADS-1:0] gpio_CORE2PAD;
wire [NUM_GPIO_PADS-1:0] gpio_CORE2PAD_OE;

generate
    for (genvar i = 0; i < NUM_GPIO_PADS; i++) begin : gpios
        sg13cmos5l_IOPadInOut30mA gpio_pad (
            `ifdef USE_POWER_PINS
            .iovdd  ( IOVDD ),
            .iovss  ( IOVSS ),
            .vdd    ( VDD   ),
            .vss    ( VSS   ),
            `endif
            .c2p    ( gpio_CORE2PAD[i]    ),
            .c2p_en ( gpio_CORE2PAD_OE[i] ),
            .p2c    ( gpio_PAD2CORE[i]    ),
            .pad    ( gpio_PAD[i]         )
        );
    end
endgenerate

// ============================================================
// QSPI0 pad instances
// ============================================================

wire [3:0]             qspi_io_PAD2CORE;
wire [3:0]             qspi_io_CORE2PAD;
wire [3:0]             qspi_io_CORE2PAD_OE;
wire                   qspi_sck_CORE2PAD;
wire [NUM_QSPI_CS-1:0] qspi_cs_CORE2PAD;

generate
    // QSPI0 I/O pads
    for (genvar i = 0; i < 4; i++) begin : qspi_ios
        sg13cmos5l_IOPadInOut30mA qspi_io_pad (
            `ifdef USE_POWER_PINS
            .iovdd  ( IOVDD ),
            .iovss  ( IOVSS ),
            .vdd    ( VDD   ),
            .vss    ( VSS   ),
            `endif
            .c2p    ( qspi_io_CORE2PAD[i]    ),
            .c2p_en ( qspi_io_CORE2PAD_OE[i] ),
            .p2c    ( qspi_io_PAD2CORE[i]    ),
            .pad    ( qspi_io_PAD[i]         )
        );
    end

    // QSPI0 CS# pads
    for (genvar i = 0; i < NUM_QSPI_CS; i++) begin : qspi_css
        sg13cmos5l_IOPadOut30mA qspi_cs_pad (
            `ifdef USE_POWER_PINS
            .iovdd  ( IOVDD ),
            .iovss  ( IOVSS ),
            .vdd    ( VDD   ),
            .vss    ( VSS   ),
            `endif
            .c2p    ( qspi_cs_CORE2PAD[i] ),
            .pad    ( qspi_cs_PAD[i]      )
        );
    end
endgenerate

// QSPI0 SCK pad
sg13cmos5l_IOPadOut30mA qspi_sck_pad (
    `ifdef USE_POWER_PINS
    .iovdd  ( IOVDD ),
    .iovss  ( IOVSS ),
    .vdd    ( VDD   ),
    .vss    ( VSS   ),
    `endif
    .c2p    ( qspi_sck_CORE2PAD ),
    .pad    ( qspi_sck_PAD      )
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

generate
    // HyperBus DQ pads
    for (genvar i = 0; i < 8; i++) begin : hb_dqs
        sg13cmos5l_IOPadInOut30mA hb_dq_pad (
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
    for (genvar i = 0; i < NUM_HB_CS; i++) begin : hb_css
        sg13cmos5l_IOPadOut30mA hb_cs_pad (
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
endgenerate

// HyperBus RWDS pad
sg13cmos5l_IOPadInOut30mA hb_rwds_pad (
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
sg13cmos5l_IOPadOut30mA hb_ck_pad (
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
sg13cmos5l_IOPadOut30mA hb_rst_pad (
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

(* keep *) friscv_chip_soc #(
    .NumGpios ( NUM_GPIO_PADS ),
    .MemChips ( NUM_HB_CS     )
) soc_inst (
    .i_clk           ( clk_PAD2CORE         ),
    .i_rstn          ( rst_n_PAD2CORE       ),
    .o_clk_out       ( clk_out_CORE2PAD     ),
    .o_end           ( /* no package pin */ ),

    // JTAG
    .i_jtag_tck      ( jtag_tck_PAD2CORE    ),
    .i_jtag_tms      ( jtag_tms_PAD2CORE    ),
    .i_jtag_trstn    ( jtag_trst_n_PAD2CORE ),
    .i_jtag_tdi      ( jtag_tdi_PAD2CORE    ),
    .o_jtag_tdo      ( jtag_tdo_CORE2PAD    ),
    .o_jtag_tdo_oe   ( /* no package pin */ ),

    // UART0
    .i_uart_rx       ( uart_rx_PAD2CORE     ),
    .o_uart_tx       ( uart_tx_CORE2PAD     ),

    // QSPI0
    .o_qspi_sck      ( qspi_sck_CORE2PAD    ),
    .o_qspi_csn      ( qspi_cs_CORE2PAD     ),
    .i_qspi_sd       ( qspi_io_PAD2CORE     ),
    .o_qspi_sd       ( qspi_io_CORE2PAD     ),
    .o_qspi_sd_oe    ( qspi_io_CORE2PAD_OE  ),

    // HyperBus
    .i_hyper_dq      ( hb_dq_PAD2CORE       ),
    .o_hyper_dq      ( hb_dq_CORE2PAD       ),
    .o_hyper_dq_oe   ( hb_dq_CORE2PAD_OE    ),
    .i_hyper_rwds    ( hb_rwds_PAD2CORE     ),
    .o_hyper_rwds    ( hb_rwds_CORE2PAD     ),
    .o_hyper_rwds_oe ( hb_rwds_CORE2PAD_OE  ),
    .o_hyper_ck      ( hb_ck_CORE2PAD       ),
    .o_hyper_csn     ( hb_cs_CORE2PAD       ),
    .o_hyper_rstn    ( hb_rst_CORE2PAD      ),

    // GPIO Port A
    .i_gpio          ( gpio_PAD2CORE        ),
    .o_gpio          ( gpio_CORE2PAD        ),
    .o_gpio_oe       ( gpio_CORE2PAD_OE     )
);

endmodule

`default_nettype wire
