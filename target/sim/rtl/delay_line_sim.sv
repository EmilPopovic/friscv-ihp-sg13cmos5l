// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Emil Popovic <mail@emilpopovic.me>

module delay_line_D4_O1_6P000 (
  input  logic       clk_i,
  input  logic [3:0] delay_i,
  output logic [0:0] clk_o
);

  localparam real TapNs [16] = '{
    0.670, 3.341, 1.911, 4.686, 1.033, 4.047, 2.713, 5.549,
    0.844, 3.338, 2.085, 4.682, 1.556, 4.043, 2.969, 5.607
  };

  real scale = 1.0;

  initial begin
    if (!$value$plusargs("hb_dly_scale=%f", scale)) scale = 1.0;
    clk_o = 1'b0;
  end

  always @(clk_i) clk_o[0] <= #(TapNs[delay_i] * scale) clk_i;

endmodule
