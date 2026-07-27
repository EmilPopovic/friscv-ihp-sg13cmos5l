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

# HyperBus, PA13..PA24
# RWDS is the PHY's read capture clock, so it takes Y9, a P-side CCIO pin.
set_property -dict { PACKAGE_PIN F19 IOSTANDARD LVCMOS33 } [get_ports {pa_io[13]}] ;# GPIO8,  pin 24  HB_DQ0
set_property -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 } [get_ports {pa_io[14]}] ;# GPIO9,  pin 21  HB_DQ1
set_property -dict { PACKAGE_PIN V8  IOSTANDARD LVCMOS33 } [get_ports {pa_io[15]}] ;# GPIO10, pin 19  HB_DQ2
set_property -dict { PACKAGE_PIN W10 IOSTANDARD LVCMOS33 } [get_ports {pa_io[16]}] ;# GPIO11, pin 23  HB_DQ3
set_property -dict { PACKAGE_PIN B20 IOSTANDARD LVCMOS33 } [get_ports {pa_io[17]}] ;# GPIO12, pin 32  HB_DQ4
set_property -dict { PACKAGE_PIN W8  IOSTANDARD LVCMOS33 } [get_ports {pa_io[18]}] ;# GPIO13, pin 33  HB_DQ5
set_property -dict { PACKAGE_PIN B19 IOSTANDARD LVCMOS33 } [get_ports {pa_io[19]}] ;# GPIO16, pin 36  HB_DQ6
set_property -dict { PACKAGE_PIN Y8  IOSTANDARD LVCMOS33 } [get_ports {pa_io[20]}] ;# GPIO19, pin 35  HB_DQ7
set_property -dict { PACKAGE_PIN Y9  IOSTANDARD LVCMOS33 } [get_ports {pa_io[21]}] ;# GPIO21, pin 40  HB_RWDS
set_property -dict { PACKAGE_PIN U7  IOSTANDARD LVCMOS33 } [get_ports {pa_io[22]}] ;# GPIO17, pin 11  HB_CK
set_property -dict { PACKAGE_PIN A20 IOSTANDARD LVCMOS33 } [get_ports {pa_io[23]}] ;# GPIO20, pin 38  HB_CS0_N
set_property -dict { PACKAGE_PIN U8  IOSTANDARD LVCMOS33 } [get_ports {pa_io[24]}] ;# GPIO22, pin 15  HB_RST_N

# QSPI0, PA5..PA12, on PMODA in Digilent Pmod SF3 order
set_property -dict { PACKAGE_PIN Y19 IOSTANDARD LVCMOS33 } [get_ports {pa_io[5]}]  ;# JA2  QSPI0_IO0
set_property -dict { PACKAGE_PIN Y16 IOSTANDARD LVCMOS33 } [get_ports {pa_io[6]}]  ;# JA3  QSPI0_IO1
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports {pa_io[7]}]  ;# JA7  QSPI0_IO2 (strap)
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {pa_io[8]}]  ;# JA8  QSPI0_IO3 (strap)
set_property -dict { PACKAGE_PIN Y17 IOSTANDARD LVCMOS33 } [get_ports {pa_io[9]}]  ;# JA4  QSPI0_SCK
set_property -dict { PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 } [get_ports {pa_io[10]}] ;# JA1  QSPI0_CS0
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports {pa_io[11]}] ;# JA9  QSPI0_CS1
set_property -dict { PACKAGE_PIN W19 IOSTANDARD LVCMOS33 } [get_ports {pa_io[12]}] ;# JA10 QSPI0_CS2

# GPIO, PA0..PA4, on PMODB; PA1..PA4 are the PLIC interrupt sources
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports {pa_io[0]}]  ;# JB1
set_property -dict { PACKAGE_PIN Y14 IOSTANDARD LVCMOS33 } [get_ports {pa_io[1]}]  ;# JB2
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports {pa_io[2]}]  ;# JB3
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports {pa_io[3]}]  ;# JB4
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports {pa_io[4]}]  ;# JB7

# Defined level when nothing is wired up; PA7/PA8 are sampled as STRAPA
set_property PULLDOWN true [get_ports {pa_io[*]}]

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
set_false_path -from [get_ports {pa_io[*]}]
set_false_path -to   [get_ports {pa_io[*]}]
