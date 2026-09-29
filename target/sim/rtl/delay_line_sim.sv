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

  function automatic real tap_ns(input logic [3:0] tap);
    case (tap)
      4'd0:    tap_ns = 0.670;
      4'd1:    tap_ns = 3.341;
      4'd2:    tap_ns = 1.911;
      4'd3:    tap_ns = 4.686;
      4'd4:    tap_ns = 1.033;
      4'd5:    tap_ns = 4.047;
      4'd6:    tap_ns = 2.713;
      4'd7:    tap_ns = 5.549;
      4'd8:    tap_ns = 0.844;
      4'd9:    tap_ns = 3.338;
      4'd10:   tap_ns = 2.085;
      4'd11:   tap_ns = 4.682;
      4'd12:   tap_ns = 1.556;
      4'd13:   tap_ns = 4.043;
      4'd14:   tap_ns = 2.969;
      default: tap_ns = 5.607;
    endcase
  endfunction

  real scale = 1.0;

  initial begin
    if (!$value$plusargs("hb_dly_scale=%f", scale)) scale = 1.0;
    clk_o = 1'b0;
  end

  always @(clk_i) clk_o[0] <= #(tap_ns(delay_i) * scale) clk_i;

endmodule
