// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/

// Blackbox stub of the HyperBus PHY delay line macro.
//
// 16 taps from 4 control bits, 6.000 ns full scale at 0.375 ns/step. Built by
// src/mc_delay/delay.tcl; views in src/mc_delay/views. Instantiated by
// rtl/soc/configurable_delay.sv under TARGET_ASIC.
`pragma diagnostic push
`pragma diagnostic ignore="-Wunused-port"
`pragma diagnostic ignore="-Wundriven-port"
(* blackbox *)
module delay_line_D4_O1_6P000 (
  input  logic       clk_i,
  input  logic [3:0] delay_i,
  output logic [0:0] clk_o
);
endmodule
`pragma diagnostic pop
