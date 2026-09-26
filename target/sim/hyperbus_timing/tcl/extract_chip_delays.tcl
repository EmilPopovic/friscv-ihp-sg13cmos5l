# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
#
# Matej Jurasić <matej.jurasic@cappig.dev>

# On-chip HyperBus path delays (hbt_chip_delays_t) at one corner, for `hbt extract`.
# Parameters come from $PARAMS (see hbtlib/extract.py). Clocks propagate from the
# clock root and from the RWDS pad, so every number is an arrival difference
# between two pins and the delay line's own arc drops out.

source $::env(PARAMS)

foreach l $libs { catch { read_liberty $l } }
read_db $odb

proc set_rc {} {
    global layer_rc signal_layers clock_layers
    foreach e $layer_rc {
        lassign $e layer r c
        set_layer_rc -layer $layer -resistance $r -capacitance $c
    }
    set_wire_rc -signal -layers $signal_layers
    set_wire_rc -clock  -layers $clock_layers
}
if { $spef ne "" } {
    read_spef $spef
    set para "spef [file tail $spef]"
} elseif { $guide ne "" } {
    set_rc
    read_guides $guide
    estimate_parasitics -global_routing
    set para "global-route parasitics"
} else {
    set_rc
    estimate_parasitics -placement
    set para "placement estimate"
}

# Pin lookup: the first of the patterns that matches, at any hierarchy depth
proc pins {patterns} {
    foreach pattern $patterns {
        foreach prefix {"" "*" "*/" "*/*/" "*/*/*/"} {
            set p [get_pins -quiet "$prefix$pattern"]
            if { [llength $p] > 0 } { return $p }
        }
    }
    error "no pins match '$patterns'"
}

# Pad instances on top-level ports, and their pins
proc pads_of {ports} {
    global pad_c2p
    set block [ord::get_db_block]
    set out {}
    foreach port [get_ports $ports] {
        foreach it [[[$block findBTerm [get_full_name $port]] getNet] getITerms] {
            set inst [$it getInst]
            if { [$inst findITerm $pad_c2p] ne "NULL" } { lappend out [$inst getName] }
        }
    }
    if { [llength $out] == 0 } { error "no pad cell on ports '$ports'" }
    return $out
}
proc pad_pins {ports pin} {
    set out {}
    foreach i [pads_of $ports] { set out [concat $out [get_pins "$i/$pin"]] }
    return $out
}

proc is_a {ref patterns} {
    foreach p $patterns { if { [string match $p $ref] } { return 1 } }
    return 0
}

# Flops are anonymous after synthesis: trace forward from named pins through
# buffers, inverters, clock gates and muxes to {pin parity lib_pin} per flop input
proc trace_fwd {start_pin} {
    global cell_flop cell_icg cell_mux cell_inv cell_buf
    global pin_icg_clk pin_icg_out pin_mux_in pin_mux_out pin_inv_out pin_buf_out
    set out {}
    set todo [list [list [get_full_name $start_pin] 0]]
    set seen [dict create]
    while { [llength $todo] > 0 } {
        lassign [lindex $todo 0] pname par
        set todo [lrange $todo 1 end]
        set net [get_nets -quiet -of_objects [get_pins $pname]]
        if { $net eq "" } { continue }
        foreach ld [get_pins -quiet -of_objects $net -filter "direction==input"] {
            set lname [get_full_name $ld]
            if { [dict exists $seen $lname] } { continue }
            dict set seen $lname 1
            set cell  [get_cells -of_objects $ld]
            set ref   [get_property $cell ref_name]
            set pin   [get_property $ld lib_pin_name]
            set cname [get_full_name $cell]
            if { [is_a $ref $cell_flop] } {
                lappend out [list $lname $par $pin]
            } elseif { [is_a $ref $cell_icg] } {
                if { $pin eq $pin_icg_clk } { lappend todo [list "$cname/$pin_icg_out" $par] }
            } elseif { [is_a $ref $cell_mux] } {
                if { [lsearch $pin_mux_in $pin] >= 0 } { lappend todo [list "$cname/$pin_mux_out" $par] }
            } elseif { [is_a $ref $cell_inv] } {
                lappend todo [list "$cname/$pin_inv_out" [expr {$par + 1}]]
            } elseif { [is_a $ref $cell_buf] } {
                lappend todo [list "$cname/$pin_buf_out" $par]
            }
        }
    }
    return $out
}

# Backward from a pin through buffers/inverters to the driving flop
proc trace_bwd {start_pin} {
    global cell_flop
    set pname [get_full_name $start_pin]
    for {set i 0} {$i < 20} {incr i} {
        set net  [get_nets -of_objects [get_pins $pname]]
        set drv  [lindex [get_pins -of_objects $net -filter "direction==output"] 0]
        set cell [get_cells -of_objects $drv]
        if { [is_a [get_property $cell ref_name] $cell_flop] } { return [get_full_name $cell] }
        set pname [get_full_name [lindex [get_pins -of_objects $cell -filter "direction==input"] 0]]
    }
    error "no flop behind [get_full_name $start_pin]"
}

proc sel {traced pinname {par -1}} {
    set out {}
    foreach t $traced {
        lassign $t p pp lp
        if { $lp eq $pinname && ($par < 0 || ($pp % 2) == $par) } { lappend out [get_pins $p] }
    }
    if { [llength $out] == 0 } { error "trace found no $pinname pins (parity $par)" }
    return $out
}

# Worst min / max arrival over rise/fall at a set of pins, from report_arrival.
# Arrivals caused by the falling clock edge are taken relative to that edge.
set HALF [expr {$period / 2.0}]
proc arrival_range {pinset {edges "^v"} {trans "rf"}} {
    global HALF
    set lo 1e9
    set hi -1e9
    foreach p $pinset {
        sta::redirect_string_begin
        report_arrival $p
        set rpt [sta::redirect_string_end]
        foreach line [split $rpt "\n"] {
            if { ![regexp {\(\S+ ([\^v])\) r (\S+):(\S+) f (\S+):(\S+)} $line -> edge r0 r1 f0 f1] } { continue }
            if { [string first $edge $edges] < 0 } { continue }
            set ofs [expr {$edge eq "v" ? $HALF : 0.0}]
            set pairs {}
            if { [string first r $trans] >= 0 } { lappend pairs $r0 $r1 }
            if { [string first f $trans] >= 0 } { lappend pairs $f0 $f1 }
            foreach {a b} $pairs {
                if { ![string is double -strict $a] || ![string is double -strict $b] } { continue }
                set a [expr {$a - $ofs}]
                set b [expr {$b - $ofs}]
                if { $a < $lo } { set lo $a }
                if { $b > $hi } { set hi $b }
            }
        }
    }
    if { $lo > 1e8 } { error "no arrivals at [get_full_name [lindex $pinset 0]]" }
    return [list $lo $hi]
}

# Same-edge difference to - from, pairing transitions as given
proc path {to from edges {pairs "rr ff"}} {
    set lo 1e9
    set hi -1e9
    foreach e [split $edges ""] {
        foreach pr $pairs {
            set tt [string index $pr 0]
            set ft [string index $pr 1]
            if { [catch { set t [arrival_range $to $e $tt]; set f [arrival_range $from $e $ft] }] } { continue }
            set a [expr {[lindex $t 0] - [lindex $f 1]}]
            set b [expr {[lindex $t 1] - [lindex $f 0]}]
            if { $a < $lo } { set lo $a }
            if { $b > $hi } { set hi $b }
        }
    }
    if { $lo > 1e8 } { error "no matching arrivals for path to [get_full_name [lindex $to 0]]" }
    return [list $lo $hi]
}

proc data_arrival {from to minmax} {
    sta::redirect_string_begin
    report_checks -path_delay $minmax -from $from -to $to -digits 4
    set rpt [sta::redirect_string_end]
    foreach line [split $rpt "\n"] {
        if { [regexp {^\s*([-0-9.]+)\s+data arrival time} $line -> t] } { return $t }
    }
    error "no path from [get_full_name $from] to [get_full_name $to]"
}

set fh [open $out w]
puts $fh "# parasitics: $para, db [file tail $odb]"
proc put {name lo hi} {
    global fh
    puts $fh [format "%-14s %8.4f %8.4f" $name $lo $hi]
}

# Pass 1: core clock from the root, RWDS as plain data from its pad
if { $clock_root eq "" } { set clock_root "[lindex [pads_of $clock_port] 0]/$pad_p2c" }
set data_ports [list $rwds_port $dq_port]
create_clock -name clk -period $period [get_pins $clock_root]
set_propagated_clock [all_clocks]
set_input_transition 0.15 [get_ports $clock_port]
set_input_delay 0 -clock clk [get_ports $data_ports]
set_input_transition 1.0 [get_ports $data_ports]

set dq_c2p   [pad_pins $dq_port $pad_c2p]
set rwds_c2p [pad_pins $rwds_port $pad_c2p]
set oe_pins  [concat [pad_pins $dq_port $pad_en] [pad_pins $rwds_port $pad_en]]
set ck_c2p   [pad_pins $ck_port $pad_c2p]
set cs_c2p   [pad_pins $cs_port $pad_c2p]

# TX DDR outputs, clock root to the pad: both clock edges (the mux select path),
# and after the rising edge alone, where the flops update and the new data follows
# the stale value through the mux data inputs
set d [arrival_range $dq_c2p]
put dq_out [lindex $d 0] [lindex $d 1]
set d [arrival_range $dq_c2p "^"]
put dq_data [lindex $d 0] [lindex $d 1]

set d [arrival_range $rwds_c2p]
put rwds_out [lindex $d 0] [lindex $d 1]
set d [arrival_range $rwds_c2p "^"]
put rwds_data [lindex $d 0] [lindex $d 1]

set d [arrival_range $oe_pins "^"]
put oe [lindex $d 0] [lindex $d 1]

# TX delay line: clock root latency to its input, then CK (through the gate)
# timed from a clock at the line's output. CS# from its flop's clock: the
# falling root clock, or the line's output.
set d [arrival_range [pins $tx_dl_in]]
put dl_tx_in [lindex $d 0] [lindex $d 1]
if { $cs_clock eq "core_fall" } {
    set d [arrival_range $cs_c2p "v"]
    put cs_out [lindex $d 0] [lindex $d 1]
}
create_clock -name txo -period $period [pins $tx_dl_out]
set_propagated_clock [all_clocks]
set d [arrival_range $ck_c2p]
put ck_out [lindex $d 0] [lindex $d 1]
if { $cs_clock ne "core_fall" } {
    set d [arrival_range $cs_c2p "^"]
    put cs_out [lindex $d 0] [lindex $d 1]
}

# Control flops on the root clock. The RWDS sample flop is the one whose D is
# reached from the RWDS pad without passing the delay line.
set rwds_p2c [pad_pins $rwds_port $pad_p2c]
set rws_d_pins [sel [trace_fwd [lindex $rwds_p2c 0]] $pin_d]
set rws_cell [get_full_name [get_cells -of_objects [lindex $rws_d_pins 0]]]
set d [arrival_range [get_pins "$rws_cell/$pin_clk"] "^" r]
put l_core [lindex $d 0] [lindex $d 1]
set d [path [get_pins "$rws_cell/$pin_q"] [get_pins "$rws_cell/$pin_clk"] "^" "rr fr"]
put ckq [lindex $d 0] [lindex $d 1]

# Crossings into the delayed clocks: data arrival at the capture pins
set cs_flop [trace_bwd [lindex $cs_c2p 0]]
set d [arrival_range [get_pins "$cs_flop/$pin_d"] "^"]
put cs_d [lindex $d 0] [lindex $d 1]
set d [arrival_range [pins $ck_gate_en] "^"]
put ckena_d [lindex $d 0] [lindex $d 1]
set d [arrival_range [pins $rx_gate_en] "^"]
put rxena_d [lindex $d 0] [lindex $d 1]

# RWDS and DQ from their pads (input delay on the rising clock edge)
set d [path [pins $rx_dl_in] $rwds_p2c "^"]
put rwds_in_dl [lindex $d 0] [lindex $d 1]
# The sample flop's D is behind an enable mux: time only the path from the pad
set pad [get_ports $rwds_port]
set rp [arrival_range $rwds_p2c "^"]
set lo [expr {[data_arrival $pad $rws_d_pins min] - [lindex $rp 0]}]
set hi [expr {[data_arrival $pad $rws_d_pins max] - [lindex $rp 1]}]
put rws_in $lo $hi

set lo 1e9
set hi -1e9
foreach p [pad_pins $dq_port $pad_p2c] {
    set d [path [sel [trace_fwd $p] $pin_d] $p "^"]
    if { [lindex $d 0] < $lo } { set lo [lindex $d 0] }
    if { [lindex $d 1] > $hi } { set hi [lindex $d 1] }
}
put dq_in $lo $hi

# RX strobe: from the RX delay line output into the capture flops
set rxo [pins $rx_dl_out]
create_clock -name rxo -period $period $rxo
set_propagated_clock [all_clocks]
set d [arrival_range [pins $rx_gate_clk] "^" r]
put rx_icg [lindex $d 0] [lindex $d 1]
set rx_clk_pins [trace_fwd [lindex $rxo 0]]
# Rising-edge capture flops see the RWDS rising edge; the FIFO write flops are
# behind the inverter and clock on the RWDS falling edge
set d [arrival_range [sel $rx_clk_pins $pin_clk 0] "^" r]
put rx_pos [lindex $d 0] [lindex $d 1]
set d [arrival_range [sel $rx_clk_pins $pin_clk 1] "v" r]
put rx_neg [lindex $d 0] [lindex $d 1]

close $fh
