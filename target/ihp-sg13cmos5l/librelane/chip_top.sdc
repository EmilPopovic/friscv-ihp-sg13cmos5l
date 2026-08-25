# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/

# Based on https://github.com/IHP-GmbH/ihp-sg13cmos5l-librelane-template/blob/main/librelane/chip_top.sdc
# HyperBus DDR modelling based on pulp-platform/cheshire-ihp130-o (basilisk.sdc).

current_design $::env(DESIGN_NAME)
set_units -time ns

##############
# Core clock #
##############

set clock_port __VIRTUAL_CLK__
# Find CLOCK_PORT in the env
if { [info exists ::env(CLOCK_PORT)] } {
    set port_count [llength $::env(CLOCK_PORT)]

    if { $port_count == "0" } {
        puts "\[WARNING] No CLOCK_PORT found. A dummy clock will be used."
    } elseif { $port_count != "1" } {
        puts "\[WARNING] Multi-clock files are not currently supported by the base SDC file. Only the first clock will be constrained."
    }

    if { $port_count > "0" } {
        set ::clock_port [lindex $::env(CLOCK_PORT) 0]
    }
}

# Use CLOCK_NET (the core-side output of the clock pad cell) as clock source to ignore the clock pad delay
if { $::env(CLOCK_PORT) == $::env(CLOCK_NET) } {
    set port_args [get_ports $clock_port]
} else {
    set port_args [get_pins [lindex $::env(CLOCK_NET) 0]]
}

# Create a clock on the given port with the period from env
puts "\[INFO] Using clock $clock_port…"
create_clock {*}$port_args -name $clock_port -period $::env(CLOCK_PERIOD)

# Input and output delay budget as IO_DELAY_CONSTRAINT% of the clock period each
set input_delay_value  [expr {$::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100.0}]
set output_delay_value [expr {$::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100.0}]
puts "\[INFO] Setting output delay to: $output_delay_value"
puts "\[INFO] Setting input delay to: $input_delay_value"

# Set global max fanout to MAX_FANOUT_CONSTRAINT
set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]
if { [info exists ::env(MAX_TRANSITION_CONSTRAINT)] } {
    set_max_transition $::env(MAX_TRANSITION_CONSTRAINT) [current_design]
}
# Apply global max capacitance of MAX_CAPACITANCE_CONSTRAINT if set
if { [info exists ::env(MAX_CAPACITANCE_CONSTRAINT)] } {
    set_max_capacitance $::env(MAX_CAPACITANCE_CONSTRAINT) [current_design]
}

# The core clock object
set clocks [get_clocks $clock_port]

###########
# Helpers #
###########

# Hierarchy-agnostic pin search
proc hyp_pins {pattern} {
    set prefix ""
    for {set i 0} {$i < 4} {incr i} {
        set pins [get_pins -quiet "$prefix$pattern"]
        if { [llength $pins] > 0 } {
            return $pins
        }
        append prefix "*/"
    }
    return {}
}

# Hierarchy-agnostic pin search, expect exactly one match
proc hyp_pin1 {pattern} {
    set pins [hyp_pins $pattern]
    if { [llength $pins] != 1 } {
        error "HyperBus: '$pattern' matched [llength $pins] pins, expected 1"
    }
    return $pins
}

# Build a bus name[0..n-1] and return the ports, error if the number of ports found is not n
proc bus_ports {name n} {
    set pats {}
    for {set i 0} {$i < $n} {incr i} { lappend pats "${name}\[$i\]" }
    set ports [get_ports $pats]
    if { [llength $ports] != $n } {
        error "pads: expected $n ports on $name, found [llength $ports]"
    }
    return $ports
}

# Similar to bus_ports, but for a generate-block array (e.g. hb_hq_pads[3].hb_dq_pad/c2p_en)
proc pad_bus_pins {fmt n pin} {
    set pats {}
    for {set i 0} {$i < $n} {incr i} { lappend pats "[format $fmt $i]/$pin" }
    set pins [get_pins $pats]
    if { [llength $pins] != $n } {
        error "pads: expected $n '$pin' pins on $fmt, found [llength $pins]"
    }
    return $pins
}

# Return a clock object for a given name, error if not matching exactly one
proc clk1 {name} {
    set c [get_clocks -quiet $name]
    if { [llength $c] != 1 } {
        error "clocks: '$name' matched [llength $c] clocks, expected 1"
    }
    return $c
}

#####################
# Named collections #
#####################

# Float of the system clock period
set TCK_SYS [expr {1.0 * $::env(CLOCK_PERIOD)}]

# Paths of delay lines producing the shifted clock
set HYP_TX_DLINE "*i_delay_tx_clk_90.i_delay.i_delay_line"
set HYP_RX_DLINE "*i_delay_rx_rwds_90.i_delay.i_delay_line"

# Bus port groups, pad-side
set GPIO_PORTS [bus_ports gpio_a_PAD 8]

set BOOT_PORTS [bus_ports boot_PAD 2]

set QSPI_IO  [bus_ports qspi0_io_PAD 4]
set QSPI_SCK [get_ports qspi0_sck_PAD]
set QSPI_CS  [bus_ports qspi0_cs_PAD 3]

set HYP_DQ_IN    [bus_ports hb_dq_PAD 8]
set HYP_RWDS     [get_ports hb_rwds_PAD]
set HYP_IO       [concat $HYP_DQ_IN $HYP_RWDS]
set HYP_OUT_COUT [get_ports hb_ck_PAD]
set HYP_OUT_CS   [bus_ports hb_cs_PAD 2]
set HYP_OUT_RST  [get_ports hb_rst_PAD]

# Output enable pins of DQ pads and RWDS pad
set HYP_OUT_DOEN [concat [pad_bus_pins "hb_dq_pads\[%d\].hb_dq_pad" 8 c2p_en] \
                         [get_pins hb_rwds_pad/c2p_en]]

####################
# Secondary clocks #
####################

# Constrain the JTAG clock for 10 MHz
set jtag_period 100
create_clock -name jtag_tck -period $jtag_period [get_ports {jtag_tck_PAD}]

# Declare RWDS as a clock, set to core clock period
create_clock -name hb_rwds -period $::env(CLOCK_PERIOD) $HYP_RWDS

# Declare the internal HyperBus clock as a clock, sourced from the delay line, set to core clock period
create_generated_clock -name hb_ck_int -divide_by 1 \
    -source [hyp_pin1 "$HYP_TX_DLINE/clk_i"] \
    [hyp_pin1 "$HYP_TX_DLINE/clk_o*"]

# Declare QSPI0 SCK pad as a clock source, set to half the core clock period (the max SPI clock)
set QSPI_SCK_SRC [get_pins qspi0_sck_pad/c2p]
create_generated_clock -name qspi0_sck -divide_by 2 \
    -source [get_pins [lindex $::env(CLOCK_NET) 0]] $QSPI_SCK_SRC

# Set the core clock/HyperBus clock/QSPI0 SCK as asynchronous to the JTAG clock
set_clock_groups -asynchronous -allow_paths \
    -group [get_clocks [list $clock_port hb_ck_int qspi0_sck]] \
    -group [get_clocks jtag_tck]

# Set everything as asynchronous to the HyperBus RWDS clock
set_clock_groups -asynchronous \
    -group [get_clocks [list $clock_port hb_ck_int qspi0_sck jtag_tck]] \
    -group [get_clocks hb_rwds]

# All clocks
set all_clocks [all_clocks]

##############
# I/O delays #
##############

set jtag_in_ports  [get_ports {jtag_tms_PAD jtag_tdi_PAD}]
set jtag_out_ports [get_ports {jtag_tdo_PAD}]

# Set external data for UART0 RX and BOOT ports as inputs, get data within input_delay_value of the core clock
set clk_core_input_ports [concat [get_ports {uart0_rx_PAD}] $BOOT_PORTS]
set_input_delay -min 0                  -clock $clocks $clk_core_input_ports
set_input_delay -max $input_delay_value -clock $clocks $clk_core_input_ports

# Heartbeat and UART0 TX must drive within output_delay_value of the core clock
set clk_core_output_ports [get_ports {heartbeat_PAD uart0_tx_PAD}]
set_output_delay $output_delay_value -clock $clocks $clk_core_output_ports

# Same input limit for inouts (GPIO and QSPI0 IO)
set clk_core_inout_ports [concat $GPIO_PORTS $QSPI_IO]
set_input_delay -min 0                  -clock $clocks $clk_core_inout_ports
set_input_delay -max $input_delay_value -clock $clocks $clk_core_inout_ports

# Output limit for GPIO and HyperBus reset
set_output_delay $output_delay_value -clock $clocks [concat $GPIO_PORTS $HYP_OUT_RST]

# Similar for JTAG, but scaled to its slower clock
set jtag_io_delay  [expr {$jtag_period * $::env(IO_DELAY_CONSTRAINT) / 100.0}]
set jtag_min_delay [expr {$jtag_period / 4.0}]
set_input_delay  -min $jtag_min_delay -clock jtag_tck $jtag_in_ports
set_input_delay  -max $jtag_io_delay  -clock jtag_tck $jtag_in_ports

set_output_delay -min [expr {$jtag_period * 0.10 / 2}] -clock jtag_tck $jtag_out_ports
set_output_delay -max $jtag_io_delay                   -clock jtag_tck $jtag_out_ports

# No hold check for UART0 RX, GPIO, and BOOT ports, they are synchronized internally
set_false_path -hold -from [concat [get_ports {uart0_rx_PAD}] $GPIO_PORTS $BOOT_PORTS]

# JTAG-core CDC constraints each way
set_max_delay $TCK_SYS     -from [get_ports rst_n_PAD]
set_false_path -hold       -from [get_ports rst_n_PAD]
set_max_delay $jtag_period -from [get_ports jtag_trst_n_PAD]
set_false_path -hold       -from [get_ports jtag_trst_n_PAD]

set CDC_MAX [expr {$TCK_SYS / 2}]

set_max_delay $CDC_MAX -from [get_clocks jtag_tck]    -to [get_clocks $clock_port]
set_max_delay $CDC_MAX -from [get_clocks $clock_port] -to [get_clocks jtag_tck]
set_false_path -hold   -from [get_clocks jtag_tck]    -to [get_clocks $clock_port]
set_false_path -hold   -from [get_clocks $clock_port] -to [get_clocks jtag_tck]

########################
# HyperBus constraints #
########################

# Max slew for HyperBus pads
set HYP_MAX_SLEW 1.5

# DDR data window, ideal center is a quarter period, so we leave HYP_MAX_SLEW of margin on both sides for slew
set HYP_DDR_MAX [expr {$TCK_SYS / 4 - $HYP_MAX_SLEW}]
set HYP_DDR_MIN [expr {$TCK_SYS / 4 + $HYP_MAX_SLEW}]

# Edge-shift corrections for DDR
set HYP_EDGE_FULL $TCK_SYS
set HYP_EDGE_HALF [expr {$TCK_SYS / 2}]

# One delay line step
set HYP_DLY_STEP 0.375

# TX skew correction
set HYP_TX_SKEW [expr {2 * $HYP_DLY_STEP}]

# The delay of the RX tree is not 90 degrees, correct it by adding a skew to the target delay
set HYP_RX_TREE_SKEW 2.25

# Measured delay line taps, not in order because it is bit-reversed in hardware
set HYP_DLY_TAPS {
    { 0 0.670}  { 8 0.844}  { 4 1.033}  {12 1.556}
    { 2 1.911}  {10 2.085}  { 6 2.713}  {14 2.969}
    { 1 3.341}  { 9 3.338}  { 5 4.047}  {13 4.043}
    { 3 4.686}  {11 4.682}  { 7 5.549}  {15 5.607}
}

##########################
# Delay line programming #
##########################

# Pick the table entry closest to the target delay, return code and delay
proc hyp_tap {target} {
    global HYP_DLY_TAPS
    set best {}
    foreach entry $HYP_DLY_TAPS {
        set code [lindex $entry 0]
        set dly  [lindex $entry 1]
        set err  [expr {abs($dly - $target)}]
        if { $best eq "" || $err < [lindex $best 2] - 0.010 } {
            set best [list $code $dly $err]
        }
    }
    return [lrange $best 0 1]
}

# Get and print the delay line tap values for TX and RX, software should use these at the target clock
set HYP_TX_TAP [hyp_tap [expr {$TCK_SYS / 4.0 + $HYP_TX_SKEW}]]
set HYP_RX_TAP [hyp_tap [expr {$TCK_SYS / 4.0 - $HYP_RX_TREE_SKEW}]]

set HYP_TX_CODE    [lindex $HYP_TX_TAP 0]
set HYP_TX_TGT_DLY [lindex $HYP_TX_TAP 1]
set HYP_RX_CODE    [lindex $HYP_RX_TAP 0]
set HYP_RX_TGT_DLY [lindex $HYP_RX_TAP 1]

puts "\[INFO] HyperBus delay-line targets: TX $HYP_TX_TGT_DLY ns (t_tx_clk_delay=$HYP_TX_CODE), RX $HYP_RX_TGT_DLY ns (t_rx_clk_delay=$HYP_RX_CODE) (TCK_SYS $TCK_SYS)"

# Get corner names from STA
set hyp_corners {}
catch { foreach c [sta::corners] { lappend hyp_corners [$c name] } }

# For each delay line, replace the macro's assigned delay with the target delay
foreach dline [list $HYP_TX_DLINE $HYP_RX_DLINE] tgt [list $HYP_TX_TGT_DLY $HYP_RX_TGT_DLY] {
    set dly_from [hyp_pin1 "$dline/clk_i"]
    set dly_to   [hyp_pin1 "$dline/clk_o*"]

    # Fallback to typical corner if no corners are defined
    if { [llength $hyp_corners] == 0 } {
        puts "\[WARNING] HyperBus: no named corners, pinning delay line to typ only"
        set_assigned_delay -cell -from $dly_from -to $dly_to $tgt
    } else {
        # Constrain fast to a lower delay, slow to a higher delay, typical to the target
        foreach cname $hyp_corners {
            if { [string match "*fast*" $cname] } {
                set dly [expr {$tgt - $HYP_DLY_STEP}]
            } elseif { [string match "*slow*" $cname] } {
                set dly [expr {$tgt + $HYP_DLY_STEP}]
            } else {
                set dly $tgt
            }
            set_assigned_delay -cell -corner $cname -from $dly_from -to $dly_to $dly
        }
    }

    # The requested delay is a static configuration, false-path it
    set_false_path -through [hyp_pins "$dline/delay_i*"]
}

#############################
# 90 degree TX clock domain #
#############################

# Clock the shifted pins from the internal hb_ck_int
set HYP_CK90_ENDS [all_registers -clock [get_clocks hb_ck_int] -data_pins]
# Gated by the internal gate of the PHY
lappend HYP_CK90_ENDS {*}[hyp_pin1 "*i_hyper_ck_gating.i_clkgate/GATE"]
set_multicycle_path -setup 0 -to $HYP_CK90_ENDS
set_multicycle_path -hold  0 -to $HYP_CK90_ENDS

#######################
# DQ and RWDS outputs #
#######################

# DQ output window for both edges relative to HyperBus clock pad
set_output_delay -max -add_delay             -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT [expr {$HYP_DDR_MAX + $HYP_EDGE_FULL}] $HYP_DQ_IN
set_output_delay -max -add_delay -clock_fall -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT [expr {$HYP_DDR_MAX + $HYP_EDGE_FULL}] $HYP_DQ_IN
set_output_delay -min -add_delay             -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT $HYP_DDR_MIN                           $HYP_DQ_IN
set_output_delay -min -add_delay -clock_fall -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT $HYP_DDR_MIN                           $HYP_DQ_IN

# Allow for a small mismatch between RWDS and CK
set HYP_PAD_MISMATCH 0.3
set HYP_RWDS_OUT     [concat [hyp_pin1 "hb_rwds_pad/c2p"] [hyp_pin1 "hb_rwds_pad/c2p_en"]]
set HYP_OUT_COUT_PRE [hyp_pin1 "hb_ck_pad/c2p"]

# Same for DDR constraints for RWDS with the mismatch
set_output_delay -max -add_delay             -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT_PRE [expr {$HYP_DDR_MAX + $HYP_PAD_MISMATCH + $HYP_EDGE_FULL}] $HYP_RWDS_OUT
set_output_delay -max -add_delay -clock_fall -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT_PRE [expr {$HYP_DDR_MAX + $HYP_PAD_MISMATCH + $HYP_EDGE_FULL}] $HYP_RWDS_OUT
set_output_delay -min -add_delay             -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT_PRE [expr {$HYP_DDR_MIN + $HYP_PAD_MISMATCH}]                  $HYP_RWDS_OUT
set_output_delay -min -add_delay -clock_fall -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT_PRE [expr {$HYP_DDR_MIN + $HYP_PAD_MISMATCH}]                  $HYP_RWDS_OUT

set_false_path -setup -rise_from [get_clocks $clock_port] -fall_to [get_clocks hb_ck_int]
set_false_path -setup -fall_from [get_clocks $clock_port] -rise_to [get_clocks hb_ck_int]

# No hold check for output enable pins
set_false_path -hold -through $HYP_OUT_DOEN

set_max_delay [expr {$HYP_TX_TGT_DLY + $TCK_SYS}] -to $HYP_OUT_COUT

# 3 ns of CS setup before the first clock edge
set HYP_TCSS 3.0
set_output_delay -max -add_delay -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT $HYP_TCSS     $HYP_OUT_CS
set_output_delay -min -add_delay -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT $HYP_MAX_SLEW $HYP_OUT_CS

# Relax requirements for HyperBus reset
set_multicycle_path -setup 2 -to $HYP_OUT_RST
set_multicycle_path -hold  1 -to $HYP_OUT_RST

######################
# DQ and RWDS inputs #
######################

# Constrain both input edges to RWDS
set_input_delay -max -add_delay             -clock [clk1 hb_rwds] -network_latency_included [expr {$HYP_DDR_MAX + $HYP_EDGE_HALF}] $HYP_DQ_IN
set_input_delay -max -add_delay -clock_fall -clock [clk1 hb_rwds] -network_latency_included [expr {$HYP_DDR_MAX + $HYP_EDGE_HALF}] $HYP_DQ_IN
set_input_delay -min -add_delay             -clock [clk1 hb_rwds] -network_latency_included $HYP_DDR_MIN                           $HYP_DQ_IN
set_input_delay -min -add_delay -clock_fall -clock [clk1 hb_rwds] -network_latency_included $HYP_DDR_MIN                           $HYP_DQ_IN

set_false_path -setup -rise_from [get_clocks hb_rwds] -fall_to [get_clocks hb_rwds]
set_false_path -setup -fall_from [get_clocks hb_rwds] -rise_to [get_clocks hb_rwds]

# Stop clocks from propagating through the DDR mux select pins
set hyper_ddr_mux_sel [hyp_pins {*i_ddrmux.i_mux/S}]
# Ensure there are 9 of them that match (RWDS, 8 DQ)
if { [llength $hyper_ddr_mux_sel] != 9 } {
    error "HyperBus: expected 9 DDR mux select pins, found [llength $hyper_ddr_mux_sel]"
}
set_sense -type clock -stop_propagation $hyper_ddr_mux_sel

###################################
# QSPI0 source-synchronous to SCK #
###################################

set QSPI_DATA [concat $QSPI_IO $QSPI_CS]

set QSPI_TSU  3.0
set QSPI_TCSS 5.0

# Setup on IO and CS relative to SCK
set_output_delay -max $QSPI_TSU  -clock [clk1 qspi0_sck] -reference_pin $QSPI_SCK -add_delay $QSPI_IO
set_output_delay -max $QSPI_TCSS -clock [clk1 qspi0_sck] -reference_pin $QSPI_SCK -add_delay $QSPI_CS

set_false_path -hold -to $QSPI_DATA
set_false_path -hold -to $QSPI_SCK

# SCK output bound to one system period
set_max_delay $TCK_SYS -to $QSPI_SCK

####################################
# Pad loads, drive and slew limits #
####################################

# Every output has 4 pF to 10 pF of load
set_load -min  4.0 [all_outputs]
set_load -max 10.0 [all_outputs]

# 1 ns input transition for all input pads
set_input_transition 1.0 [concat $GPIO_PORTS $BOOT_PORTS $QSPI_IO $HYP_DQ_IN \
    [get_ports {rst_n_PAD jtag_tms_PAD jtag_tdi_PAD jtag_trst_n_PAD uart0_rx_PAD}]]

# Setup uncertainty for all clocks
puts "\[INFO] Setting clock setup uncertainty to: $::env(CLOCK_UNCERTAINTY_CONSTRAINT)"
set_clock_uncertainty -setup $::env(CLOCK_UNCERTAINTY_CONSTRAINT) $all_clocks

# Hold uncertainty for all clocks
puts "\[INFO] Setting clock hold uncertainty to: 0.05"
set_clock_uncertainty -hold 0.05 $all_clocks

# Clock transition for all clocks
puts "\[INFO] Setting clock transition to: $::env(CLOCK_TRANSITION_CONSTRAINT)"
set_clock_transition $::env(CLOCK_TRANSITION_CONSTRAINT) $all_clocks

puts "\[INFO] Setting timing derate to: $::env(TIME_DERATING_CONSTRAINT)%"
set_timing_derate -early [expr {1 - $::env(TIME_DERATING_CONSTRAINT) / 100.0}]
set_timing_derate -late  [expr {1 + $::env(TIME_DERATING_CONSTRAINT) / 100.0}]

# Ideal clocks before CTS
if { [info exists ::env(OPENLANE_SDC_IDEAL_CLOCKS)] && $::env(OPENLANE_SDC_IDEAL_CLOCKS) } {
    unset_propagated_clock [all_clocks]
} else {
    set_propagated_clock [all_clocks]
}
