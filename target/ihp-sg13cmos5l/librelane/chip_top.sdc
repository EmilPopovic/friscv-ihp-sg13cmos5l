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
    set port_args [get_pins [lindex $::env(CLOCK_NET) 0]]
}

puts "\[INFO] Using clock $clock_port…"
create_clock {*}$port_args -name $clock_port -period $::env(CLOCK_PERIOD)

set input_delay_value  [expr {$::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100.0}]
set output_delay_value [expr {$::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100.0}]
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

proc hyp_pin1 {pattern} {
    set pins [hyp_pins $pattern]
    if { [llength $pins] != 1 } {
        error "HyperBus: '$pattern' matched [llength $pins] pins, expected 1"
    }
    return $pins
}

proc bus_ports {name n} {
    set pats {}
    for {set i 0} {$i < $n} {incr i} { lappend pats "${name}\[$i\]" }
    set ports [get_ports $pats]
    if { [llength $ports] != $n } {
        error "pads: expected $n ports on $name, found [llength $ports]"
    }
    return $ports
}

proc pad_bus_pins {fmt n pin} {
    set pats {}
    for {set i 0} {$i < $n} {incr i} { lappend pats "[format $fmt $i]/$pin" }
    set pins [get_pins $pats]
    if { [llength $pins] != $n } {
        error "pads: expected $n '$pin' pins on $fmt, found [llength $pins]"
    }
    return $pins
}

proc clk1 {name} {
    set c [get_clocks -quiet $name]
    if { [llength $c] != 1 } {
        error "clocks: '$name' matched [llength $c] clocks, expected 1"
    }
    return $c
}

set TCK_SYS [expr {1.0 * $::env(CLOCK_PERIOD)}]

set HYP_TX_DLINE "*i_delay_tx_clk_90.i_delay.i_delay_line"
set HYP_RX_DLINE "*i_delay_rx_rwds_90.i_delay.i_delay_line"

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

set HYP_OUT_DOEN [concat [pad_bus_pins "hb_dq_pads\[%d\].hb_dq_pad" 8 c2p_en] \
                         [get_pins hb_rwds_pad/c2p_en]]

# ============================================================
# Secondary clock domains
# ============================================================

set jtag_period 100
create_clock -name jtag_tck -period $jtag_period [get_ports {jtag_tck_PAD}]

create_clock -name hb_rwds -period $::env(CLOCK_PERIOD) $HYP_RWDS

create_generated_clock -name hb_ck_int -divide_by 1 \
    -source [hyp_pin1 "$HYP_TX_DLINE/clk_i"] \
    [hyp_pin1 "$HYP_TX_DLINE/clk_o*"]

set QSPI_SCK_SRC [get_pins qspi0_sck_pad/c2p]
create_generated_clock -name qspi0_sck -divide_by 2 \
    -source [get_pins [lindex $::env(CLOCK_NET) 0]] $QSPI_SCK_SRC

set_clock_groups -asynchronous -allow_paths \
    -group [get_clocks [list $clock_port hb_ck_int qspi0_sck]] \
    -group [get_clocks jtag_tck]

set_clock_groups -asynchronous \
    -group [get_clocks [list $clock_port hb_ck_int qspi0_sck jtag_tck]] \
    -group [get_clocks hb_rwds]

set all_clocks [all_clocks]

# ============================================================
# I/O delays
# ============================================================

set jtag_in_ports  [get_ports {jtag_tms_PAD jtag_tdi_PAD}]
set jtag_out_ports [get_ports {jtag_tdo_PAD}]

set clk_core_input_ports [concat [get_ports {uart0_rx_PAD}] $BOOT_PORTS]
set_input_delay -min 0                  -clock $clocks $clk_core_input_ports
set_input_delay -max $input_delay_value -clock $clocks $clk_core_input_ports

set clk_core_output_ports [get_ports {clk_out_PAD uart0_tx_PAD}]
set_output_delay $output_delay_value -clock $clocks $clk_core_output_ports

set clk_core_inout_ports [concat $GPIO_PORTS $QSPI_IO]
set_input_delay -min 0                  -clock $clocks $clk_core_inout_ports
set_input_delay -max $input_delay_value -clock $clocks $clk_core_inout_ports

set_output_delay $output_delay_value -clock $clocks [concat $GPIO_PORTS $HYP_OUT_RST]

set jtag_io_delay  [expr {$jtag_period * $::env(IO_DELAY_CONSTRAINT) / 100.0}]
set jtag_min_delay [expr {$jtag_period / 4.0}]
set_input_delay  -min $jtag_min_delay -clock jtag_tck $jtag_in_ports
set_input_delay  -max $jtag_io_delay  -clock jtag_tck $jtag_in_ports

set_output_delay -min [expr {$jtag_period * 0.10 / 2}] -clock jtag_tck $jtag_out_ports
set_output_delay -max $jtag_io_delay                   -clock jtag_tck $jtag_out_ports

set_false_path -hold -from [concat [get_ports {uart0_rx_PAD}] $GPIO_PORTS $BOOT_PORTS]

set_max_delay $TCK_SYS     -from [get_ports rst_n_PAD]
set_false_path -hold       -from [get_ports rst_n_PAD]
set_max_delay $jtag_period -from [get_ports jtag_trst_n_PAD]
set_false_path -hold       -from [get_ports jtag_trst_n_PAD]

set CDC_MAX [expr {$TCK_SYS / 2}]

set_max_delay $CDC_MAX -from [get_clocks jtag_tck]    -to [get_clocks $clock_port]
set_max_delay $CDC_MAX -from [get_clocks $clock_port] -to [get_clocks jtag_tck]
set_false_path -hold   -from [get_clocks jtag_tck]    -to [get_clocks $clock_port]
set_false_path -hold   -from [get_clocks $clock_port] -to [get_clocks jtag_tck]

# ============================================================
# HyperBus
# ============================================================

set HYP_MAX_SLEW 1.5

set HYP_DDR_MAX [expr {$TCK_SYS / 4 - $HYP_MAX_SLEW}]
set HYP_DDR_MIN [expr {$TCK_SYS / 4 + $HYP_MAX_SLEW}]

set HYP_EDGE_FULL $TCK_SYS
set HYP_EDGE_HALF [expr {$TCK_SYS / 2}]

# ============================================================
# Delay lines
# ============================================================

set HYP_DLY_STEP 0.375
set HYP_DLY_FS   6.000

set HYP_TX_SKEW      $HYP_DLY_STEP
set HYP_RX_TREE_SKEW 1.0

proc hyp_tap {target step fs} {
    set taps [expr {round(double($target) / $step)}]
    if { $taps < 1 } { set taps 1 }
    if { $taps * $step > $fs } { set taps [expr {int($fs / $step)}] }
    return [expr {$taps * $step}]
}

set HYP_TX_TGT_DLY [hyp_tap [expr {$TCK_SYS / 4.0 + $HYP_TX_SKEW}]   $HYP_DLY_STEP $HYP_DLY_FS]
set HYP_RX_TGT_DLY [hyp_tap [expr {$TCK_SYS / 4.0 - $HYP_RX_TREE_SKEW}] $HYP_DLY_STEP $HYP_DLY_FS]

puts "\[INFO] HyperBus delay-line targets: TX $HYP_TX_TGT_DLY ns, RX $HYP_RX_TGT_DLY ns (TCK_SYS $TCK_SYS)"

set hyp_corners {}
catch { foreach c [sta::corners] { lappend hyp_corners [$c name] } }

foreach dline [list $HYP_TX_DLINE $HYP_RX_DLINE] tgt [list $HYP_TX_TGT_DLY $HYP_RX_TGT_DLY] {
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

    set_false_path -through [hyp_pins "$dline/delay_i*"]
}

# ============================================================
# 90-degree TX clock domain
# ============================================================

set HYP_CK90_ENDS [all_registers -clock [get_clocks hb_ck_int] -data_pins]
lappend HYP_CK90_ENDS {*}[hyp_pin1 "*i_hyper_ck_gating.i_clkgate/GATE"]
set_multicycle_path -setup 0 -to $HYP_CK90_ENDS
set_multicycle_path -hold  0 -to $HYP_CK90_ENDS

# ============================================================
# DDR output: DQ and RWDS
# ============================================================

set_output_delay -max -add_delay             -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT [expr {$HYP_DDR_MAX + $HYP_EDGE_FULL}] $HYP_DQ_IN
set_output_delay -max -add_delay -clock_fall -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT [expr {$HYP_DDR_MAX + $HYP_EDGE_FULL}] $HYP_DQ_IN
set_output_delay -min -add_delay             -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT $HYP_DDR_MIN                           $HYP_DQ_IN
set_output_delay -min -add_delay -clock_fall -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT $HYP_DDR_MIN                           $HYP_DQ_IN

set HYP_PAD_MISMATCH 0.3
set HYP_RWDS_OUT     [concat [hyp_pin1 "hb_rwds_pad/c2p"] [hyp_pin1 "hb_rwds_pad/c2p_en"]]
set HYP_OUT_COUT_PRE [hyp_pin1 "hb_ck_pad/c2p"]

set_output_delay -max -add_delay             -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT_PRE [expr {$HYP_DDR_MAX + $HYP_PAD_MISMATCH + $HYP_EDGE_FULL}] $HYP_RWDS_OUT
set_output_delay -max -add_delay -clock_fall -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT_PRE [expr {$HYP_DDR_MAX + $HYP_PAD_MISMATCH + $HYP_EDGE_FULL}] $HYP_RWDS_OUT
set_output_delay -min -add_delay             -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT_PRE [expr {$HYP_DDR_MIN + $HYP_PAD_MISMATCH}]                  $HYP_RWDS_OUT
set_output_delay -min -add_delay -clock_fall -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT_PRE [expr {$HYP_DDR_MIN + $HYP_PAD_MISMATCH}]                  $HYP_RWDS_OUT

set_false_path -setup -rise_from [get_clocks $clock_port] -fall_to [get_clocks hb_ck_int]
set_false_path -setup -fall_from [get_clocks $clock_port] -rise_to [get_clocks hb_ck_int]

set_false_path -hold -through $HYP_OUT_DOEN

set_max_delay [expr {$HYP_TX_TGT_DLY + $TCK_SYS}] -to $HYP_OUT_COUT

set HYP_TCSS 3.0
set_output_delay -max -add_delay -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT $HYP_TCSS     $HYP_OUT_CS
set_output_delay -min -add_delay -clock [clk1 hb_ck_int] -reference_pin $HYP_OUT_COUT $HYP_MAX_SLEW $HYP_OUT_CS

set_multicycle_path -setup 2 -to $HYP_OUT_RST
set_multicycle_path -hold  1 -to $HYP_OUT_RST

# ============================================================
# DDR input: DQ and RWDS
# ============================================================

set_input_delay -max -add_delay             -clock [clk1 hb_rwds] -network_latency_included [expr {$HYP_DDR_MAX + $HYP_EDGE_HALF}] $HYP_DQ_IN
set_input_delay -max -add_delay -clock_fall -clock [clk1 hb_rwds] -network_latency_included [expr {$HYP_DDR_MAX + $HYP_EDGE_HALF}] $HYP_DQ_IN
set_input_delay -min -add_delay             -clock [clk1 hb_rwds] -network_latency_included $HYP_DDR_MIN                           $HYP_DQ_IN
set_input_delay -min -add_delay -clock_fall -clock [clk1 hb_rwds] -network_latency_included $HYP_DDR_MIN                           $HYP_DQ_IN

set_false_path -setup -rise_from [get_clocks hb_rwds] -fall_to [get_clocks hb_rwds]
set_false_path -setup -fall_from [get_clocks hb_rwds] -rise_to [get_clocks hb_rwds]

set hyper_ddr_mux_sel [hyp_pins {*i_ddrmux.i_mux/S}]
if { [llength $hyper_ddr_mux_sel] != 9 } {
    error "HyperBus: expected 9 DDR mux select pins, found [llength $hyper_ddr_mux_sel]"
}
set_sense -type clock -stop_propagation $hyper_ddr_mux_sel

# ============================================================
# QSPI0 source-synchronous to SCK
# ============================================================

set QSPI_DATA [concat $QSPI_IO $QSPI_CS]

set QSPI_TSU  3.0
set QSPI_TCSS 5.0

set_output_delay -max $QSPI_TSU  -clock [clk1 qspi0_sck] -reference_pin $QSPI_SCK -add_delay $QSPI_IO
set_output_delay -max $QSPI_TCSS -clock [clk1 qspi0_sck] -reference_pin $QSPI_SCK -add_delay $QSPI_CS

set_false_path -hold -to $QSPI_DATA
set_false_path -hold -to $QSPI_SCK

set_max_delay $TCK_SYS -to $QSPI_SCK

# ============================================================
# Pad loads, drive and slew limits
# ============================================================

set_load -min  4.0 [all_outputs]
set_load -max 10.0 [all_outputs]

set_input_transition 1.0 [concat $GPIO_PORTS $BOOT_PORTS $QSPI_IO $HYP_DQ_IN \
    [get_ports {rst_n_PAD jtag_tms_PAD jtag_tdi_PAD jtag_trst_n_PAD uart0_rx_PAD}]]

set_max_transition 4.0 [all_outputs]

puts "\[INFO] Setting clock setup uncertainty to: $::env(CLOCK_UNCERTAINTY_CONSTRAINT)"
set_clock_uncertainty -setup $::env(CLOCK_UNCERTAINTY_CONSTRAINT) $all_clocks

puts "\[INFO] Setting clock hold uncertainty to: 0.05"
set_clock_uncertainty -hold 0.05 $all_clocks

puts "\[INFO] Setting clock transition to: $::env(CLOCK_TRANSITION_CONSTRAINT)"
set_clock_transition $::env(CLOCK_TRANSITION_CONSTRAINT) $all_clocks

puts "\[INFO] Setting timing derate to: $::env(TIME_DERATING_CONSTRAINT)%"
set_timing_derate -early [expr {1 - $::env(TIME_DERATING_CONSTRAINT) / 100.0}]
set_timing_derate -late  [expr {1 + $::env(TIME_DERATING_CONSTRAINT) / 100.0}]

if { [info exists ::env(OPENLANE_SDC_IDEAL_CLOCKS)] && $::env(OPENLANE_SDC_IDEAL_CLOCKS) } {
    unset_propagated_clock [all_clocks]
} else {
    set_propagated_clock [all_clocks]
}
