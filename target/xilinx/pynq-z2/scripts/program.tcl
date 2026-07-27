# Load the PL over the board's PROG micro-USB. JP4 must select JTAG boot.

open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target

set pl ""
foreach d [get_hw_devices] { if {[string match "xc7z020*" $d]} { set pl $d } }
if {$pl eq ""} { error "no xc7z020 in the JTAG chain: [get_hw_devices]" }

current_hw_device $pl
refresh_hw_device -update_hw_probes false $pl
set_property PROGRAM.FILE $::env(BIT) $pl
program_hw_devices $pl

close_hw_target
disconnect_hw_server
close_hw_manager
