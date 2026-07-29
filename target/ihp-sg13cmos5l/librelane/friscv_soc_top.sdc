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
# Secondary clock domains
# ============================================================

# JTAG TCK, 10 MHz
set jtag_period 100
create_clock -name jtag_tck -period $jtag_period [get_ports {input_PAD[0]}]

# HyperBus RWDS
create_clock -name hb_rwds -period $::env(CLOCK_PERIOD) [get_ports {bidir_PAD[21]}]

# Set domains as asynchronous to each other
set_clock_groups -asynchronous \
    -group [get_clocks $clock_port] \
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
set_output_delay $output_delay_value -clock $clocks $clk_core_inout_ports

# JTAG data pins timed against TCK
set jtag_io_delay  [expr $jtag_period * $::env(IO_DELAY_CONSTRAINT) / 100]
set jtag_min_delay [expr $jtag_period / 4.0]
set_input_delay  -min $jtag_min_delay -clock jtag_tck $jtag_in_ports
set_input_delay  -max $jtag_io_delay  -clock jtag_tck $jtag_in_ports
set_output_delay $jtag_io_delay       -clock jtag_tck $jtag_out_ports

# Asynchronous pad inputs, no hold
set_false_path -hold -from [get_ports {bidir_PAD[0] bidir_PAD[1] bidir_PAD[2] bidir_PAD[3] bidir_PAD[4]}]

set cap_load [expr $::env(OUTPUT_CAP_LOAD) / 1000.0]
puts "\[INFO] Setting load to: $cap_load"
set_load $cap_load [all_outputs]

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
