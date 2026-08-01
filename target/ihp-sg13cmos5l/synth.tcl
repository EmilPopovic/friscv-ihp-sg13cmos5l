set here         [file dirname [file normalize [info script]]]
set liberty      $::env(LIBERTY)
set sram_liberty $::env(SRAM_LIBERTY)

set sram_lib_dir $::env(PDK_ROOT)/ihp-sg13g2/libs.ref/sg13g2_sram/lib
set way_sram_liberty \
    $sram_lib_dir/RM_IHPSG13_1P_512x32_c2_bm_bist_typ_1p20V_25C.lib
set tag_sram_liberty \
    $sram_lib_dir/RM_IHPSG13_1P_64x64_c2_bm_bist_typ_1p20V_25C.lib

# Elaborate all bender sources through slang
yosys read_slang --top friscv_soc --keep-hierarchy --timescale 1ns/1ps \
    -Wno-duplicate-definition --ignore-initial --ignore-timing \
    -f $here/sources.f

# Coarse synth
yosys hierarchy -top friscv_soc
yosys synth -top friscv_soc
yosys dfflibmap -liberty $liberty
yosys abc -fast -liberty $liberty
yosys opt_clean

# Hierarchical area total across all submodules
yosys tee -o $here/area.rpt stat -liberty $liberty -liberty $sram_liberty \
    -liberty $way_sram_liberty -liberty $tag_sram_liberty -top friscv_soc
