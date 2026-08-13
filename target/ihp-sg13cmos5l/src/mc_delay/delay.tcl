# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Authors:
#  - Thomas Benz <tbenz@iis.ee.ethz.ch>
#  - Emil Popović <mail@emilpopovic.me>

# ToDo: Timing should be on point, it fixes slack too much
#       -> check window-constraint, maybe add hold-margin and relax slack-margin?

# flow parameters
if {![info exists ::env(DESIGN_NAME)]} {
    set DESIGN_NAME delay_line_D4_O1_6P000
} else {
    set DESIGN_NAME $::env(DESIGN_NAME)
}

set pdk_dir $::env(PDK_ROOT)/$::env(PDK)/libs.ref/sg13cmos5l_stdcell

exec mkdir -p reports

# lib
define_corners tt
read_liberty -corner tt ${pdk_dir}/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
read_lef ${pdk_dir}//lef/sg13cmos5l_tech.lef
read_lef ${pdk_dir}//lef/sg13cmos5l_stdcell.lef


# read netlist
read_verilog ${DESIGN_NAME}.v
link_design ${DESIGN_NAME}

read_sdc delay_line_D4_O1_6P000.sdc


set ASPECT 1.0
set UTIL 75
set DENSITY [expr (1.0*$UTIL)/100]

# --- TRIAL PLACEMENT ---
# creates an oversized floorplan to repair netlist so we can get post-repair design-area
initialize_floorplan -utilization [expr $UTIL/3] -aspect_ratio $ASPECT -site CoreSite -core_space 0

# initialize tracks
make_tracks Metal1    -x_offset 0 -x_pitch 0.48 -y_offset 0 -y_pitch 0.42
make_tracks Metal2    -x_offset 0 -x_pitch 0.48 -y_offset 0 -y_pitch 0.42
make_tracks Metal3    -x_offset 0 -x_pitch 0.48 -y_offset 0 -y_pitch 0.42
make_tracks Metal4    -x_offset 0 -x_pitch 0.48 -y_offset 0 -y_pitch 0.42
#make_tracks Metal5    -x_offset 0 -x_pitch 0.48 -y_offset 0 -y_pitch 0.42
make_tracks TopMetal1 -x_offset 1.64 -x_pitch 3.28 -y_offset 1.64 -y_pitch 3.28
#make_tracks TopMetal2 -x_offset 2.00 -x_pitch 4.00 -y_offset 2.00 -y_pitch 4.00

set_wire_rc -signal -layer Metal3
set_wire_rc -clock  -layer Metal3

# global placement
# low final overflow so global-place actually solves it instead of detailed_placement
global_placement -density $DENSITY -skip_io -overflow 0.00000001

place_pins -hor_layers Metal3 -ver_layers Metal2

detailed_placement
optimize_mirroring

estimate_parasitics -placement
repair_timing -allow_setup_violations -hold -hold_margin 0.4 -repair_tns 100
repair_timing -setup -repair_tns 100

# detail placement
detailed_placement
optimize_mirroring

# --- TRIAL PLACEMENT COMPLETED ---

# properly resize floorplan to achieve target utilization
set area [sta::format_area [rsz::design_area] 0]
set area [expr $area / $DENSITY]

set block      [ord::get_db_block]
set first_row  [lindex [$block getRows] 0]
set row_site   [$first_row getSite]
# the step size is 1 core-site high and 1 core-site wide
set x_step     [ord::dbu_to_microns [$row_site getWidth]]
set y_step     [ord::dbu_to_microns [$row_site getHeight]]

set width  [expr {ceil(sqrt($area / $ASPECT))}]
set height [expr {ceil($width * $ASPECT)}]

set width_rounded [expr {ceil($width/$x_step) * $x_step}]
set height_rounded [expr {ceil($height/$y_step) * $y_step}]
set coords [list 0.0 0.0 $width_rounded $height_rounded]

# initialize the proper floorplan
initialize_floorplan -die_area $coords -core_area $coords -site CoreSite

# initialize_floorplan discards the tracks made for the trial floorplan, so
# remake them here or place_pins/routing find none (PPL-0021).
make_tracks Metal1    -x_offset 0 -x_pitch 0.48 -y_offset 0 -y_pitch 0.42
make_tracks Metal2    -x_offset 0 -x_pitch 0.48 -y_offset 0 -y_pitch 0.42
make_tracks Metal3    -x_offset 0 -x_pitch 0.48 -y_offset 0 -y_pitch 0.42
make_tracks Metal4    -x_offset 0 -x_pitch 0.48 -y_offset 0 -y_pitch 0.42
make_tracks TopMetal1 -x_offset 1.64 -x_pitch 3.28 -y_offset 1.64 -y_pitch 3.28

# very low target overflow to get close-to-usable placement
global_placement -density $DENSITY -timing_driven -skip_io -overflow 0.00000001
# fix placement
detailed_placement
optimize_mirroring

# Add power and ground connections to pins named VDD and VSS
add_global_connection -net VDD -inst_pattern .* -pin_pattern VDD -power
add_global_connection -net VSS -inst_pattern .* -pin_pattern VSS -ground
global_connect

set_voltage_domain -name CORE -power VDD -ground VSS

# Create a PDN grid on Metal4
define_pdn_grid -name macro_pdn -voltage_domains CORE -starts_with POWER -pins {Metal4}
add_pdn_stripe -grid macro_pdn -layer Metal1 -width 0.44 -followpins
add_pdn_stripe -grid macro_pdn -layer Metal4 -width 1.2 -pitch 14.0 -spacing 4.0 -offset 4.0 -starts_with POWER -extend_to_boundary
add_pdn_connect -grid macro_pdn -layers {Metal1 Metal4}
pdngen -verbose

# move pins
# cmos5l Metal2 is VERTICAL and Metal3 HORIZONTAL - the opposite of sg13g2, so
# these two are swapped relative to upstream.
place_pins -hor_layers Metal3 -ver_layers Metal2

# no fixing here, we do it after GRT again
estimate_parasitics -placement

# global route
set_global_routing_layer_adjustment Metal1-Metal3 0.0
set_routing_layers -signal Metal2-Metal3 -clock Metal2-Metal3
global_route -guide_file reports/route.guide -verbose

# final timing repair
estimate_parasitics -global_routing
repair_timing -allow_setup_violations -hold -repair_tns 100
repair_timing -setup -repair_tns 100
global_route -start_incremental
detailed_placement
optimize_mirroring
global_route -end_incremental -guide_file reports/route.guide -verbose

# detail place
set_thread_count 8
detailed_route -output_drc reports/route_drc.rpt \
               -output_maze reports/maze.log \
               -save_guide_updates \
               -verbose 1
# -bottom_routing_layer / -top_routing_layer were removed from detailed_route
# (DRT-0509); the set_routing_layers call above already bounds it to Metal2-3.

# add fillers
filler_placement "*fill*"
check_placement
report_checks -path_delay min -format full_clock_expanded >  reports/timings.rpt
report_checks -path_delay max -format full_clock_expanded >> reports/timings.rpt

# write files out
exec mkdir -p out
write_timing_model out/$DESIGN_NAME.lib
write_lef out/$DESIGN_NAME.lef
write_abstract_lef out/$DESIGN_NAME.abst.lef
write_def out/$DESIGN_NAME.def
write_verilog out/$DESIGN_NAME.v
write_sdf out/$DESIGN_NAME.sdf
write_sdc out/$DESIGN_NAME.sdc
# write_spef out/$DESIGN_NAME.spef
