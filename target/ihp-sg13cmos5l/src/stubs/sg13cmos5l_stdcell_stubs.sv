// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/

// Blackbox stubs of the sg13cmos5l stdcells instantiated directly by the
// tech cell wrappers (tc_clk.sv). Ports match the PDK liberty/verilog views.
`pragma diagnostic push
`pragma diagnostic ignore="-Wunused-port"
`pragma diagnostic ignore="-Wundriven-port"

(* blackbox *)
module sg13cmos5l_inv_1 (
  input  logic A,
  output logic Y
);
endmodule

(* blackbox *)
module sg13cmos5l_buf_1 (
  input  logic A,
  output logic X
);
endmodule

(* blackbox *)
module sg13cmos5l_dlygate4sd3_1 (
  input  logic A,
  output logic X
);
endmodule

(* blackbox *)
module sg13cmos5l_and2_1 (
  input  logic A,
  input  logic B,
  output logic X
);
endmodule

(* blackbox *)
module sg13cmos5l_or2_1 (
  input  logic A,
  input  logic B,
  output logic X
);
endmodule

(* blackbox *)
module sg13cmos5l_xor2_1 (
  input  logic A,
  input  logic B,
  output logic X
);
endmodule

(* blackbox *)
module sg13cmos5l_mux2_1 (
  input  logic A0,
  input  logic A1,
  input  logic S,
  output logic X
);
endmodule

(* blackbox *)
module sg13cmos5l_slgcp_1 (
  output logic GCLK,
  input  logic GATE,
  input  logic CLK,
  input  logic SCE
);
endmodule

`pragma diagnostic pop
