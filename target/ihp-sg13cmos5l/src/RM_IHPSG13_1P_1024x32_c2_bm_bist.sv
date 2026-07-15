// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/

// Blackbox stub of the IHP SG13 single-port 1024x32 SRAM macro
`pragma diagnostic push
`pragma diagnostic ignore="-Wunused-port"
`pragma diagnostic ignore="-Wundriven-port"
(* blackbox *)
module RM_IHPSG13_1P_1024x32_c2_bm_bist (
  input  logic        A_CLK,
  input  logic        A_MEN,
  input  logic        A_WEN,
  input  logic        A_REN,
  input  logic [9:0]  A_ADDR,
  input  logic [31:0] A_DIN,
  input  logic        A_DLY,
  output logic [31:0] A_DOUT,
  input  logic [31:0] A_BM,
  input  logic        A_BIST_CLK,
  input  logic        A_BIST_EN,
  input  logic        A_BIST_MEN,
  input  logic        A_BIST_WEN,
  input  logic        A_BIST_REN,
  input  logic [9:0]  A_BIST_ADDR,
  input  logic [31:0] A_BIST_DIN,
  input  logic [31:0] A_BIST_BM
);
endmodule
`pragma diagnostic pop
