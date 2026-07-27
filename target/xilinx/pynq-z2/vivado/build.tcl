set here   [file dirname [file normalize [info script]]]
set target [file dirname $here]
set outdir $::env(OUTDIR)
set top    $::env(TOP)

file mkdir $outdir/reports

# Split the bender flist into include dirs, defines and sources
set incdirs {}
set defines {}
set files   {}
set fh [open $::env(FLIST)]
foreach line [split [read $fh] "\n"] {
    set line [string trim $line]
    if {$line eq ""} continue
    if {[string match "+incdir+*" $line]} {
        lappend incdirs [string range $line 8 end]
    } elseif {[string match "+define+*" $line]} {
        lappend defines -verilog_define [string range $line 8 end]
    } else {
        lappend files $line
    }
}
close $fh

# FPGA_EMUL picks the fabric DDR mux in the HyperBus PHY, so tc_clk_mux2 does
# not become a BUFGMUX on 9 data pins
lappend defines -verilog_define FPGA_EMUL
if {$::env(SRAM_INIT) ne ""} {
    lappend defines -verilog_define "FRISCV_SRAM_INIT=\"$::env(SRAM_INIT)\""
}

read_verilog -sv $files
read_xdc $target/constraints/friscv_soc_pynq.xdc

# auto_detect_xpm hangs here, so name the library directly
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]

synth_design -top $top -part $::env(PART) -include_dirs $incdirs \
    -generic SramCfg=$::env(SRAM_CFG) -generic ZsblRom=$::env(ZSBL) {*}$defines

write_checkpoint -force $outdir/post_synth.dcp
report_utilization -file $outdir/reports/synth_util.rpt
if {$::env(STAGE) eq "synth"} { exit 0 }

# No PS7 instantiated
set_property SEVERITY {Warning} [get_drc_checks ZPS7-1]
opt_design

place_design
phys_opt_design
route_design

write_checkpoint -force $outdir/post_route.dcp
report_utilization    -file $outdir/reports/util.rpt
report_timing_summary -file $outdir/reports/timing.rpt
report_drc            -file $outdir/reports/drc.rpt

set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
set met [expr {$wns >= 0 && $whs >= 0}]

set fh [open $outdir/reports/summary.txt w]
puts $fh "part $::env(PART)  sram_cfg $::env(SRAM_CFG)  zsbl $::env(ZSBL)"
puts $fh "sram_init [expr {$::env(SRAM_INIT) eq "" ? {none} : $::env(SRAM_INIT)}]"
puts $fh "WNS $wns  WHS $whs  [expr {$met ? {MET} : {VIOLATED}}]"
close $fh

if {$::env(STAGE) eq "bitstream"} { write_bitstream -force $outdir/$top.bit }

puts "WNS $wns  WHS $whs  [expr {$met ? {TIMING MET} : {TIMING VIOLATED}}]"
if {!$met} { exit 1 }
