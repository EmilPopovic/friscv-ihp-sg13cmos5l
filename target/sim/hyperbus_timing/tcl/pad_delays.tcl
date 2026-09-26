# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
#
# Matej Jurasić <matej.jurasic@cappig.dev>

# HyperBus pad delays at one corner and load, for `hbt char`.
# Parameters come from $PARAMS (see hbtlib/char.py); output "<arc> <rise_ns> <fall_ns>".

source $::env(PARAMS)

foreach l $libs { read_liberty $l }
read_verilog $netlist
link_design hb_pads

set_load $load_pf [get_ports {pad_io pad_o}]
set_input_transition $core_slew [get_ports {c2p_io c2p_en_io c2p_o}]
set_input_transition $pad_slew  [get_ports pad_io]
set_case_analysis $en_on [get_ports c2p_en_io]

proc arr {dir from to} {
    sta::redirect_string_begin
    report_checks -unconstrained -path_delay max -${dir}_from [get_ports $from] -to [get_ports $to] -digits 4
    set rpt [sta::redirect_string_end]
    foreach line [split $rpt "\n"] {
        if { [regexp {^\s*([0-9.]+)\s+data arrival time} $line -> t] } { return $t }
    }
    error "no $dir arrival $from -> $to"
}

set fh [open $out w]
puts $fh "out    [arr rise c2p_o pad_o]  [arr fall c2p_o pad_o]"
puts $fh "io_out [arr rise c2p_io pad_io] [arr fall c2p_io pad_io]"
puts $fh "io_in  [arr rise pad_io p2c_io] [arr fall pad_io p2c_io]"
unset_case_analysis [get_ports c2p_en_io]
puts $fh "io_en  [arr rise c2p_en_io pad_io] [arr fall c2p_en_io pad_io]"
close $fh
