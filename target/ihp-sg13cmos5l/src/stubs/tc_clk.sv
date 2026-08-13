// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Emil Popović <mail@emilpopovic.me>

// IHP sg13cmos5l implementations of the tech_cells_generic clock cells

`pragma diagnostic push
`pragma diagnostic ignore="-Wunused-def"
`pragma diagnostic ignore="-Wunused-parameter"
`pragma diagnostic ignore="-Wconstant-conversion"

module tc_clk_inverter (
  input  logic clk_i,
  output logic clk_o
);
  (* keep *)(* dont_touch = "true" *)
  sg13cmos5l_inv_1 i_inv (
    .A ( clk_i ),
    .Y ( clk_o )
  );
endmodule

module tc_clk_buffer (
  input  logic clk_i,
  output logic clk_o
);
  (* keep *)(* dont_touch = "true" *)
  sg13cmos5l_buf_1 i_buf (
    .A ( clk_i ),
    .X ( clk_o )
  );
endmodule

module tc_clk_mux2 (
  input  logic clk0_i,
  input  logic clk1_i,
  input  logic clk_sel_i,
  output logic clk_o
);
  (* keep *)(* dont_touch = "true" *)
  sg13cmos5l_mux2_1 i_mux (
    .A0 ( clk0_i    ),
    .A1 ( clk1_i    ),
    .S  ( clk_sel_i ),
    .X  ( clk_o     )
  );
endmodule

module tc_clk_gating #(
  parameter bit IS_FUNCTIONAL = 1'b1
)(
  input  logic clk_i,
  input  logic en_i,
  input  logic test_en_i,
  output logic clk_o
);
  (* keep *)(* dont_touch = "true" *)
  sg13cmos5l_slgcp_1 i_clkgate (
    .GATE ( en_i      ),
    .SCE  ( test_en_i ),
    .CLK  ( clk_i     ),
    .GCLK ( clk_o     )
  );
endmodule

module tc_clk_and2 (
  input  logic clk0_i,
  input  logic clk1_i,
  output logic clk_o
);
  (* keep *)(* dont_touch = "true" *)
  sg13cmos5l_and2_1 i_and (
    .A ( clk0_i ),
    .B ( clk1_i ),
    .X ( clk_o  )
  );
endmodule

module tc_clk_xor2 (
  input  logic clk0_i,
  input  logic clk1_i,
  output logic clk_o
);
  (* keep *)(* dont_touch = "true" *)
  sg13cmos5l_xor2_1 i_xor (
    .A ( clk0_i ),
    .B ( clk1_i ),
    .X ( clk_o  )
  );
endmodule

module tc_clk_or2 (
  input  logic clk0_i,
  input  logic clk1_i,
  output logic clk_o
);
  (* keep *)(* dont_touch = "true" *)
  sg13cmos5l_or2_1 i_or (
    .A ( clk0_i ),
    .B ( clk1_i ),
    .X ( clk_o  )
  );
endmodule

`ifndef SYNTHESIS
module tc_clk_delay #(
  parameter int unsigned Delay = 300ps
) (
  input  logic in_i,
  output logic out_o
);
// pragma translate_off
`ifndef VERILATOR
  assign #(Delay) out_o = in_i;
`endif
// pragma translate_on
endmodule
`endif

`pragma diagnostic pop
