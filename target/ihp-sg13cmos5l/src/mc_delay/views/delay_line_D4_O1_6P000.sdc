###############################################################################
# Created by write_sdc
# Mon Aug  3 18:19:11 2026
###############################################################################
current_design delay_line_D4_O1_6P000
###############################################################################
# Timing Constraints
###############################################################################
set_input_delay 0.0000 -add_delay [get_ports {clk_i}]
set_input_delay 0.0000 -add_delay [get_ports {delay_i[0]}]
set_input_delay 0.0000 -add_delay [get_ports {delay_i[1]}]
set_input_delay 0.0000 -add_delay [get_ports {delay_i[2]}]
set_input_delay 0.0000 -add_delay [get_ports {delay_i[3]}]
set_output_delay 0.0000 -add_delay [get_ports {clk_o[0]}]
group_path -name dly_000_00000\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m0o0/A0}]\
    -to [get_ports {clk_o[0]}]
group_path -name dly_000_00001\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m0o0/A1}]\
    -to [get_ports {clk_o[0]}]
group_path -name dly_000_00002\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m1o0/A0}]\
    -to [get_ports {clk_o[0]}]
group_path -name dly_000_00003\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m1o0/A1}]\
    -to [get_ports {clk_o[0]}]
group_path -name dly_000_00004\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m2o0/A0}]\
    -to [get_ports {clk_o[0]}]
group_path -name dly_000_00005\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m2o0/A1}]\
    -to [get_ports {clk_o[0]}]
group_path -name dly_000_00006\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m3o0/A0}]\
    -to [get_ports {clk_o[0]}]
group_path -name dly_000_00007\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m3o0/A1}]\
    -to [get_ports {clk_o[0]}]
group_path -name dly_000_00008\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m4o0/A0}]\
    -to [get_ports {clk_o[0]}]
group_path -name dly_000_00009\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m4o0/A1}]\
    -to [get_ports {clk_o[0]}]
group_path -name dly_000_00010\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m5o0/A0}]\
    -to [get_ports {clk_o[0]}]
group_path -name dly_000_00011\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m5o0/A1}]\
    -to [get_ports {clk_o[0]}]
group_path -name dly_000_00012\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m6o0/A0}]\
    -to [get_ports {clk_o[0]}]
group_path -name dly_000_00013\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m6o0/A1}]\
    -to [get_ports {clk_o[0]}]
group_path -name dly_000_00014\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m7o0/A0}]\
    -to [get_ports {clk_o[0]}]
group_path -name dly_000_00015\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m7o0/A1}]\
    -to [get_ports {clk_o[0]}]
set_min_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m0o0/A0}]\
    -to [get_ports {clk_o[0]}] 0.2000
set_min_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m0o0/A1}]\
    -to [get_ports {clk_o[0]}] 0.5750
set_min_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m1o0/A0}]\
    -to [get_ports {clk_o[0]}] 0.9500
set_min_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m1o0/A1}]\
    -to [get_ports {clk_o[0]}] 1.3250
set_min_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m2o0/A0}]\
    -to [get_ports {clk_o[0]}] 1.7000
set_min_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m2o0/A1}]\
    -to [get_ports {clk_o[0]}] 2.0750
set_min_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m3o0/A0}]\
    -to [get_ports {clk_o[0]}] 2.4500
set_min_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m3o0/A1}]\
    -to [get_ports {clk_o[0]}] 2.8250
set_min_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m4o0/A0}]\
    -to [get_ports {clk_o[0]}] 3.2000
set_min_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m4o0/A1}]\
    -to [get_ports {clk_o[0]}] 3.5750
set_min_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m5o0/A0}]\
    -to [get_ports {clk_o[0]}] 3.9500
set_min_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m5o0/A1}]\
    -to [get_ports {clk_o[0]}] 4.3250
set_min_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m6o0/A0}]\
    -to [get_ports {clk_o[0]}] 4.7000
set_min_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m6o0/A1}]\
    -to [get_ports {clk_o[0]}] 5.0750
set_min_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m7o0/A0}]\
    -to [get_ports {clk_o[0]}] 5.4500
set_min_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m7o0/A1}]\
    -to [get_ports {clk_o[0]}] 5.8250
set_max_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m0o0/A0}]\
    -to [get_ports {clk_o[0]}] 0.4000
set_max_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m0o0/A1}]\
    -to [get_ports {clk_o[0]}] 0.7750
set_max_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m1o0/A0}]\
    -to [get_ports {clk_o[0]}] 1.1500
set_max_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m1o0/A1}]\
    -to [get_ports {clk_o[0]}] 1.5250
set_max_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m2o0/A0}]\
    -to [get_ports {clk_o[0]}] 1.9000
set_max_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m2o0/A1}]\
    -to [get_ports {clk_o[0]}] 2.2750
set_max_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m3o0/A0}]\
    -to [get_ports {clk_o[0]}] 2.6500
set_max_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m3o0/A1}]\
    -to [get_ports {clk_o[0]}] 3.0250
set_max_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m4o0/A0}]\
    -to [get_ports {clk_o[0]}] 3.4000
set_max_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m4o0/A1}]\
    -to [get_ports {clk_o[0]}] 3.7750
set_max_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m5o0/A0}]\
    -to [get_ports {clk_o[0]}] 4.1500
set_max_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m5o0/A1}]\
    -to [get_ports {clk_o[0]}] 4.5250
set_max_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m6o0/A0}]\
    -to [get_ports {clk_o[0]}] 4.9000
set_max_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m6o0/A1}]\
    -to [get_ports {clk_o[0]}] 5.2750
set_max_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m7o0/A0}]\
    -to [get_ports {clk_o[0]}] 5.6500
set_max_delay\
    -from [get_ports {clk_i}]\
    -through [get_pins {i_mx_l3m7o0/A1}]\
    -to [get_ports {clk_o[0]}] 6.0250
###############################################################################
# Environment
###############################################################################
set_load -pin_load 0.0200 [get_ports {clk_o[0]}]
set_input_transition 0.1000 [get_ports {clk_i}]
set_input_transition 0.1000 [get_ports {delay_i[3]}]
set_input_transition 0.1000 [get_ports {delay_i[2]}]
set_input_transition 0.1000 [get_ports {delay_i[1]}]
set_input_transition 0.1000 [get_ports {delay_i[0]}]
###############################################################################
# Design Rules
###############################################################################
