# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/

# Based on https://github.com/IHP-GmbH/ihp-sg13cmos5l-librelane-template/blob/main/librelane/chip_top.sdc

current_design $::env(DESIGN_NAME)
set_units -time ns

set clock_port __VIRTUAL_CLK__
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

if { $::env(CLOCK_PORT) == $::env(CLOCK_NET) } {
    set port_args [get_ports $clock_port]
} else {
    # This should actually use CLOCK_PIN?
    set port_args [get_pins [lindex $::env(CLOCK_NET) 0]]
}

puts "\[INFO] Using clock $clock_port…"
create_clock {*}$port_args -name $clock_port -period $::env(CLOCK_PERIOD)

set input_delay_value [expr $::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100]
set output_delay_value [expr $::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100]
puts "\[INFO] Setting output delay to: $output_delay_value"
puts "\[INFO] Setting input delay to: $input_delay_value"

set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]
if { [info exists ::env(MAX_TRANSITION_CONSTRAINT)] } {
    set_max_transition $::env(MAX_TRANSITION_CONSTRAINT) [current_design]
}
if { [info exists ::env(MAX_CAPACITANCE_CONSTRAINT)] } {
    set_max_capacitance $::env(MAX_CAPACITANCE_CONSTRAINT) [current_design]
}

set clocks [get_clocks $clock_port]

# ============================================================
# HyperBus handles
# ============================================================

set TCK_SYS [expr {1.0 * $::env(CLOCK_PERIOD)}]

# Two hardened delay-line macro instances
set HYP_TX_DLINE "*i_delay_tx_clk_90.i_delay.i_delay_line"
set HYP_RX_DLINE "*i_delay_rx_rwds_90.i_delay.i_delay_line"

# get_pins for a pattern that must match exactly one pin
proc hyp_pin1 {pattern} {
    set pins [get_pins $pattern]
    if { [llength $pins] != 1 } {
        error "HyperBus: '$pattern' matched [llength $pins] pins, expected 1"
    }
    return $pins
}

# get_pins over a list of muxed-pad indices
proc hyp_pad_pins {idxs pin} {
    set pats {}
    foreach i $idxs { lappend pats "bidirs\[$i\].bidir_pad/$pin" }
    set pins [get_pins $pats]
    if { [llength $pins] != [llength $idxs] } {
        error "HyperBus: expected [llength $idxs] '$pin' pad pins, found [llength $pins]"
    }
    return $pins
}

# get_ports over a list of muxed-pad indices
proc hyp_pad_ports {idxs} {
    set pats {}
    foreach i $idxs { lappend pats "bidir_PAD\[$i\]" }
    set ports [get_ports $pats]
    if { [llength $ports] != [llength $idxs] } {
        error "HyperBus: expected [llength $idxs] pad ports, found [llength $ports]"
    }
    return $ports
}

# ============================================================
# Secondary clock domains
# ============================================================

# JTAG TCK, 10 MHz
set jtag_period 100
create_clock -name jtag_tck -period $jtag_period [get_ports {input_PAD[0]}]

# HyperBus RWDS
create_clock -name hb_rwds -period $::env(CLOCK_PERIOD) [get_ports {bidir_PAD[21]}]

# The quarter-period-shifted clock that leaves the chip as HB_CK
create_generated_clock -name hb_ck_int -divide_by 1 \
    -source [hyp_pin1 "$HYP_TX_DLINE/clk_i"] \
    [hyp_pin1 "$HYP_TX_DLINE/clk_o*"]

# Set domains as asynchronous to each other
set_clock_groups -asynchronous \
    -group [get_clocks [list $clock_port hb_ck_int]] \
    -group [get_clocks jtag_tck] \
    -group [get_clocks hb_rwds]

set all_clocks [all_clocks]

# ============================================================
# I/O delays
# ============================================================

set jtag_in_ports  [get_ports {input_PAD[1] input_PAD[2]}]
set jtag_out_ports [get_ports {output_PAD[1]}]

# Input-only pads
set clk_core_input_ports [get_ports {rst_n_PAD input_PAD[3]}]

set_input_delay -min 0 -clock $clocks $clk_core_input_ports
set_input_delay -max $input_delay_value -clock $clocks $clk_core_input_ports

# Output-only pads
# [0]=CLK_OUT, [2]=UART0_TX. [1]=TDO is in the TCK domain
set clk_core_output_ports [get_ports {output_PAD[0] output_PAD[2]}]

set_output_delay $output_delay_value -clock $clocks $clk_core_output_ports

# Bidirectional pads, all except PA21 (bidir_PAD[21] = HB RWDS, a clock source)
set core_inout_names {}
for {set i 0} {$i < 25} {incr i} {
	if { $i == 21 } { continue }
	lappend core_inout_names "bidir_PAD\[$i\]"
}
set clk_core_inout_ports [get_ports $core_inout_names]

set_input_delay -min 0 -clock $clocks $clk_core_inout_ports
set_input_delay -max $input_delay_value -clock $clocks $clk_core_inout_ports

set core_inout_out_names {}
for {set i 0} {$i < 25} {incr i} {
	if { $i >= 13 && $i <= 22 } { continue }
	lappend core_inout_out_names "bidir_PAD\[$i\]"
}
set_output_delay $output_delay_value -clock $clocks [get_ports $core_inout_out_names]

# JTAG data pins timed against TCK
set jtag_io_delay  [expr $jtag_period * $::env(IO_DELAY_CONSTRAINT) / 100]
set jtag_min_delay [expr $jtag_period / 4.0]
set_input_delay  -min $jtag_min_delay -clock jtag_tck $jtag_in_ports
set_input_delay  -max $jtag_io_delay  -clock jtag_tck $jtag_in_ports
set_output_delay $jtag_io_delay       -clock jtag_tck $jtag_out_ports

# Asynchronous pad inputs, no hold
set_false_path -hold -from [get_ports {input_PAD[3] bidir_PAD[0] bidir_PAD[1] bidir_PAD[2] bidir_PAD[3] bidir_PAD[4] bidir_PAD[5] bidir_PAD[6] bidir_PAD[7] bidir_PAD[8] bidir_PAD[9] bidir_PAD[10] bidir_PAD[11] bidir_PAD[12]}]

# ============================================================
# HyperBus
# ============================================================

# Source-synchronous DDR interface, modelled after Basilisk
# (pulp-platform/cheshire-ihp130-o, target/ihp13/openroad/src/basilisk.sdc),

# An edge that takes this long to resolve is not data
set HYP_MAX_SLEW 0.75
if { [info exists ::env(MAX_TRANSITION_CONSTRAINT)] } {
    set HYP_MAX_SLEW $::env(MAX_TRANSITION_CONSTRAINT)
}

# Center-aligned DDR puts the CK edge in the middle of a T/2 bit, the data
# transition belongs a quarter period ahead of it, and may wander by the slew
# allowance either way; transition in [CK - T/4 - slew, CK - T/4 + slew]
set HYP_DDR_MAX [expr {$TCK_SYS / 4 - $HYP_MAX_SLEW}]
set HYP_DDR_MIN [expr {$TCK_SYS / 4 + $HYP_MAX_SLEW}]

set HYP_IO_IDX   {13 14 15 16 17 18 19 20 21}  ;# DQ[7:0] + RWDS
set HYP_DQ_IDX   {13 14 15 16 17 18 19 20}     ;# DQ[7:0] alone

set HYP_IO       [hyp_pad_ports $HYP_IO_IDX]   ;# DQ + RWDS, data both ways
set HYP_DQ_IN    [hyp_pad_ports $HYP_DQ_IDX]   ;# read data, captured on RWDS
set HYP_OUT_COUT [hyp_pad_ports {22}]          ;# CK: the timing reference
set HYP_OUT_CS   [hyp_pad_ports {23}]
set HYP_OUT_RST  [hyp_pad_ports {24}]

set HYP_OUT_DOEN [hyp_pad_pins $HYP_IO_IDX c2p_en]

# ------------------------------------------------------------
# Delay lines
# ------------------------------------------------------------

# configurable_delay maps to the hardened delay_line_D4_O1_6P000 macro
#
# The tap is a calibrated quantity, firmware sweeps HYPERBUS.T_TX_CLK_DELAY
# until the eye is centred, so what STA models is the calibrated delay plus
# the residual trim error.

set HYP_DLY_STEP   0.375
set HYP_TX_TGT_DLY 4.875
set HYP_RX_TGT_DLY 4.125

set hyp_corners {}
catch { foreach c [sta::corners] { lappend hyp_corners [$c name] } }

foreach dline [list $HYP_TX_DLINE $HYP_RX_DLINE] \
        tgt   [list $HYP_TX_TGT_DLY $HYP_RX_TGT_DLY] {
    set dly_from [hyp_pin1 "$dline/clk_i"]
    set dly_to   [hyp_pin1 "$dline/clk_o*"]

    if { [llength $hyp_corners] == 0 } {
        puts "\[WARNING] HyperBus: no named corners, pinning delay line to typ only"
        set_assigned_delay -cell -from $dly_from -to $dly_to $tgt
    } else {
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

    set_false_path -through [get_pins "$dline/delay_i*"]
}

# ------------------------------------------------------------
# The 90-degree TX clock domain
# ------------------------------------------------------------

# CK leaves the chip as the delayed clock while DQ/RWDS transition on the
# undelayed one, that is what centres the data on the CK edge. It also puts the
# two registers clocked by the delayed clock a quarter cycle after their
# launch registers.

set HYP_CK90_ENDS [all_registers -clock [get_clocks hb_ck_int] -data_pins]
lappend HYP_CK90_ENDS {*}[hyp_pin1 "*i_hyper_ck_gating.i_clkgate/GATE"]
set_multicycle_path -setup 0 -to $HYP_CK90_ENDS
set_multicycle_path -hold  0 -to $HYP_CK90_ENDS

# ------------------------------------------------------------
# DDR output: DQ and RWDS
# ------------------------------------------------------------

set_output_delay -max -add_delay             -clock hb_ck_int -reference_pin $HYP_OUT_COUT $HYP_DDR_MAX $HYP_IO
set_output_delay -max -add_delay -clock_fall -clock hb_ck_int -reference_pin $HYP_OUT_COUT $HYP_DDR_MAX $HYP_IO
set_output_delay -min -add_delay             -clock hb_ck_int -reference_pin $HYP_OUT_COUT $HYP_DDR_MIN $HYP_IO
set_output_delay -min -add_delay -clock_fall -clock hb_ck_int -reference_pin $HYP_OUT_COUT $HYP_DDR_MIN $HYP_IO

set_false_path -hold -through $HYP_OUT_DOEN

set_max_delay [expr {$HYP_TX_TGT_DLY + $TCK_SYS / 2}] -to $HYP_OUT_COUT

# CS is edge-aligned with CK rather than centred, and single data rate
set_output_delay -max -add_delay -clock hb_ck_int -reference_pin $HYP_OUT_COUT $HYP_MAX_SLEW                         $HYP_OUT_CS
set_output_delay -min -add_delay -clock hb_ck_int -reference_pin $HYP_OUT_COUT [expr {$TCK_SYS / 2 - $HYP_MAX_SLEW}] $HYP_OUT_CS

set_multicycle_path -setup 2 -to $HYP_OUT_RST
set_multicycle_path -hold  1 -to $HYP_OUT_RST

# ------------------------------------------------------------
# DDR input: DQ and RWDS
# ------------------------------------------------------------

# Reads are captured on RWDS, not on the system clock, so the DQ inputs are
# timed against the RWDS clock as well. Transitions happen at the edge-aligned
# input clock edges rather than between them, which makes the arrival interval
# (-T/4 + skew, T/4 - skew) around each edge.

set_input_delay -max -add_delay             -clock hb_rwds -network_latency_included $HYP_DDR_MAX $HYP_DQ_IN
set_input_delay -max -add_delay -clock_fall -clock hb_rwds -network_latency_included $HYP_DDR_MAX $HYP_DQ_IN
set_input_delay -min -add_delay             -clock hb_rwds -network_latency_included $HYP_DDR_MIN $HYP_DQ_IN
set_input_delay -min -add_delay -clock_fall -clock hb_rwds -network_latency_included $HYP_DDR_MIN $HYP_DQ_IN

# ------------------------------------------------------------
# DDR output muxes
# ------------------------------------------------------------

set hyper_ddr_mux_sel [get_pins {*i_ddrmux.i_mux/S}]
if { [llength $hyper_ddr_mux_sel] != 9 } {
    error "HyperBus: expected 9 DDR mux select pins, found [llength $hyper_ddr_mux_sel]"
}
set_sense -type clock -stop_propagation $hyper_ddr_mux_sel

set cap_load [expr $::env(OUTPUT_CAP_LOAD) / 1000.0]
puts "\[INFO] Setting load to: $cap_load"
set_load $cap_load [all_outputs]

# ============================================================
# Pad loads and slew limits
# ============================================================

set_load -min  4.0 $HYP_IO
set_load -max 10.0 $HYP_IO
set_load -min  4.0 [concat $HYP_OUT_COUT $HYP_OUT_CS $HYP_OUT_RST]
set_load -max 10.0 [concat $HYP_OUT_COUT $HYP_OUT_CS $HYP_OUT_RST]

puts "\[INFO] Setting clock setup uncertainty to: $::env(CLOCK_UNCERTAINTY_CONSTRAINT)"
set_clock_uncertainty -setup $::env(CLOCK_UNCERTAINTY_CONSTRAINT) $all_clocks

puts "\[INFO] Setting clock hold uncertainty to: 0.05"
set_clock_uncertainty -hold 0.05 $all_clocks

puts "\[INFO] Setting clock transition to: $::env(CLOCK_TRANSITION_CONSTRAINT)"
set_clock_transition $::env(CLOCK_TRANSITION_CONSTRAINT) $all_clocks

puts "\[INFO] Setting timing derate to: $::env(TIME_DERATING_CONSTRAINT)%"
set_timing_derate -early [expr 1-[expr $::env(TIME_DERATING_CONSTRAINT) / 100]]
set_timing_derate -late [expr 1+[expr $::env(TIME_DERATING_CONSTRAINT) / 100]]

if { [info exists ::env(OPENLANE_SDC_IDEAL_CLOCKS)] && $::env(OPENLANE_SDC_IDEAL_CLOCKS) } {
    unset_propagated_clock [all_clocks]
} else {
    set_propagated_clock [all_clocks]
}
