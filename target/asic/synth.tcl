set here    [file dirname [file normalize [info script]]]
set liberty $::env(LIBERTY)

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
yosys tee -o $here/area.rpt stat -liberty $liberty -top friscv_soc
