# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
#
# Matej Jurasić <matej.jurasic@cappig.dev>

# Delay of every tap of the delay line at one corner, for `hbt char`.
# Parameters come from $PARAMS (see hbtlib/char.py); output "<code> <rise_ns> <fall_ns>".

source $::env(PARAMS)

foreach l $libs { read_liberty $l }
foreach l $lefs { read_lef $l }
if { $mode eq "sdf" } {
    read_verilog $netlist
    link_design $design
    read_sdf $sdf
} else {
    read_def $def
    set_wire_rc -signal -layer $rc_layer
    set_wire_rc -clock  -layer $rc_layer
    estimate_parasitics -placement
}

set_input_transition $in_slew [get_ports $clk_in]
set_load $out_load [get_ports $clk_out]

proc arrival {dir} {
    global clk_in clk_out
    sta::redirect_string_begin
    report_checks -unconstrained -path_delay max -${dir}_from [get_ports $clk_in] -to [get_ports $clk_out] -digits 4
    set rpt [sta::redirect_string_end]
    foreach line [split $rpt "\n"] {
        if { [regexp {^\s*([0-9.]+)\s+data arrival time} $line -> t] } { return $t }
    }
    error "no arrival for the $dir edge:\n$rpt"
}

set fh [open $out w]
puts $fh "# $design mode=$mode in_slew=$in_slew out_load=$out_load"
for {set code 0} {$code < $n_codes} {incr code} {
    for {set b 0} {$b < [llength $sel_pins]} {incr b} {
        set_case_analysis [expr {($code >> $b) & 1}] [get_ports [lindex $sel_pins $b]]
    }
    puts $fh [format "%d %.4f %.4f" $code [arrival rise] [arrival fall]]
}
close $fh
