# Design constraints for friscv_soc_pynq;
#
# HyperBus sits on the Raspberry Pi GPIO header, whose pins run straight to the
# fabric; the PMOD and Arduino connectors have series resistors. RPi GPIO 0..7
# are shared with PMODA, so PMODA and those pins cannot both be used.

set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports clk_125_i]
create_clock -period 8.000 -name clk_125 [get_ports clk_125_i]

set_property -dict { PACKAGE_PIN D19 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports btn_rst_i]

set_property -dict { PACKAGE_PIN R14 IOSTANDARD LVCMOS33 } [get_ports {led_o[0]}]
set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports {led_o[1]}]
set_property -dict { PACKAGE_PIN N16 IOSTANDARD LVCMOS33 } [get_ports {led_o[2]}]
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports {led_o[3]}]

# JTAG, UART0, clock monitor
# TCK drives a BUFGMUX, so it needs the P side of a clock-capable pin: a plain
# pin fails Place 30-574, the N side fails DRC PLIO-9. U7, Y9, Y7 are P-side.
set_property -dict { PACKAGE_PIN C20 IOSTANDARD LVCMOS33 PULLUP   true } [get_ports jtag_tdi_i]  ;# GPIO18, pin 12
set_property -dict { PACKAGE_PIN W6  IOSTANDARD LVCMOS33 PULLUP   true } [get_ports jtag_tms_i]  ;# GPIO23, pin 16
set_property -dict { PACKAGE_PIN Y7  IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports jtag_tck_i]  ;# GPIO24, pin 18
set_property -dict { PACKAGE_PIN F20 IOSTANDARD LVCMOS33                } [get_ports jtag_tdo_o] ;# GPIO25, pin 22
set_property -dict { PACKAGE_PIN V6  IOSTANDARD LVCMOS33                } [get_ports uart_tx_o]  ;# GPIO14, pin 8
set_property -dict { PACKAGE_PIN Y6  IOSTANDARD LVCMOS33 PULLUP   true } [get_ports uart_rx_i]   ;# GPIO15, pin 10
set_property -dict { PACKAGE_PIN W9  IOSTANDARD LVCMOS33                } [get_ports clk_out_o]  ;# GPIO26, pin 37

# HyperBus
# RWDS is the PHY's read capture clock, so it takes Y9, a P-side CCIO pin.
set_property -dict { PACKAGE_PIN F19 IOSTANDARD LVCMOS33 } [get_ports {hb_dq_io[0]}] ;# GPIO8,  pin 24  HB_DQ0
set_property -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 } [get_ports {hb_dq_io[1]}] ;# GPIO9,  pin 21  HB_DQ1
set_property -dict { PACKAGE_PIN V8  IOSTANDARD LVCMOS33 } [get_ports {hb_dq_io[2]}] ;# GPIO10, pin 19  HB_DQ2
set_property -dict { PACKAGE_PIN W10 IOSTANDARD LVCMOS33 } [get_ports {hb_dq_io[3]}] ;# GPIO11, pin 23  HB_DQ3
set_property -dict { PACKAGE_PIN B20 IOSTANDARD LVCMOS33 } [get_ports {hb_dq_io[4]}] ;# GPIO12, pin 32  HB_DQ4
set_property -dict { PACKAGE_PIN W8  IOSTANDARD LVCMOS33 } [get_ports {hb_dq_io[5]}] ;# GPIO13, pin 33  HB_DQ5
set_property -dict { PACKAGE_PIN B19 IOSTANDARD LVCMOS33 } [get_ports {hb_dq_io[6]}] ;# GPIO16, pin 36  HB_DQ6
set_property -dict { PACKAGE_PIN Y8  IOSTANDARD LVCMOS33 } [get_ports {hb_dq_io[7]}] ;# GPIO19, pin 35  HB_DQ7
set_property -dict { PACKAGE_PIN Y9  IOSTANDARD LVCMOS33 } [get_ports hb_rwds_io]    ;# GPIO21, pin 40  HB_RWDS
set_property -dict { PACKAGE_PIN U7  IOSTANDARD LVCMOS33 } [get_ports hb_ck_o]       ;# GPIO17, pin 11  HB_CK
set_property -dict { PACKAGE_PIN A20 IOSTANDARD LVCMOS33 } [get_ports {hb_cs_o[0]}]  ;# GPIO20, pin 38  HB_CS0_N
set_property -dict { PACKAGE_PIN U13 IOSTANDARD LVCMOS33 } [get_ports {hb_cs_o[1]}]  ;# Arduino A2      HB_CS1_N
set_property -dict { PACKAGE_PIN U8  IOSTANDARD LVCMOS33 } [get_ports hb_rst_o]      ;# GPIO22, pin 15  HB_RST_N

# QSPI0 on PMODA
set_property -dict { PACKAGE_PIN Y19 IOSTANDARD LVCMOS33 } [get_ports {qspi_io[0]}]  ;# JA2  QSPI0_IO0
set_property -dict { PACKAGE_PIN Y16 IOSTANDARD LVCMOS33 } [get_ports {qspi_io[1]}]  ;# JA3  QSPI0_IO1
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports {qspi_io[2]}]  ;# JA7  QSPI0_IO2
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {qspi_io[3]}]  ;# JA8  QSPI0_IO3
set_property -dict { PACKAGE_PIN Y17 IOSTANDARD LVCMOS33 } [get_ports qspi_sck_o]    ;# JA4  QSPI0_SCK
set_property -dict { PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 } [get_ports {qspi_cs_o[0]}];# JA1  QSPI0_CS0_N
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports {qspi_cs_o[1]}];# JA9  QSPI0_CS1_N
set_property -dict { PACKAGE_PIN W19 IOSTANDARD LVCMOS33 } [get_ports {qspi_cs_o[2]}];# JA10 QSPI0_CS2_N

# GPIO Port A
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports {gpio_io[0]}]  ;# JB1
set_property -dict { PACKAGE_PIN Y14 IOSTANDARD LVCMOS33 } [get_ports {gpio_io[1]}]  ;# JB2
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports {gpio_io[2]}]  ;# JB3
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports {gpio_io[3]}]  ;# JB4
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports {gpio_io[4]}]  ;# JB7
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 } [get_ports {gpio_io[5]}]  ;# JB8
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports {gpio_io[6]}]  ;# JB9
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports {gpio_io[7]}]  ;# JB10
set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS33 } [get_ports {gpio_io[8]}]  ;# Arduino A0
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports {gpio_io[9]}]  ;# Arduino A1

set_property PULLDOWN true [get_ports {gpio_io[*]}]
set_property PULLDOWN true [get_ports {qspi_io[*]}]
set_property PULLDOWN true [get_ports {hb_dq_io[*]}]
set_property PULLDOWN true [get_ports hb_rwds_io]

# Timing
create_clock -period 100.000 -name jtag_tck [get_ports jtag_tck_i]
set_input_delay  -clock jtag_tck -max 20.000 [get_ports {jtag_tms_i jtag_tdi_i}]
set_input_delay  -clock jtag_tck -min 0.000  [get_ports {jtag_tms_i jtag_tdi_i}]
set_output_delay -clock jtag_tck -max 20.000 [get_ports jtag_tdo_o]
set_output_delay -clock jtag_tck -min 0.000  [get_ports jtag_tdo_o]
set_clock_groups -asynchronous \
    -group [get_clocks jtag_tck] \
    -group [get_clocks -include_generated_clocks clk_125]

# HyperBus and QSPI I/O timing is unconstrained: the pins are brought out for
# observation, not qualified against a device.
set_false_path -from [get_ports btn_rst_i]
set_false_path -from [get_ports uart_rx_i]
set_false_path -to   [get_ports uart_tx_o]
set_false_path -to   [get_ports {led_o[*]}]
set_false_path -to   [get_ports clk_out_o]
set_false_path -from [get_ports {gpio_io[*] qspi_io[*] hb_dq_io[*] hb_rwds_io}]
set_false_path -to   [get_ports {gpio_io[*] qspi_io[*] hb_dq_io[*] hb_rwds_io}]
set_false_path -to   [get_ports {qspi_sck_o qspi_cs_o[*]}]
set_false_path -to   [get_ports {hb_ck_o hb_cs_o[*] hb_rst_o}]
