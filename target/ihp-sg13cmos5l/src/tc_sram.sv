// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/

// Based on https://github.com/pulp-platform/cheshire-ihp130-o/blob/main/target/ihp13/src/tc_sram.sv

module tc_sram_blackbox #(
  parameter int unsigned NumWords     = 32'd0,
  parameter int unsigned DataWidth    = 32'd0,
  parameter int unsigned ByteWidth    = 32'd0,
  parameter int unsigned NumPorts     = 32'd0,
  parameter int unsigned Latency      = 32'd0,
  parameter              SimInit      = "none",
  parameter bit          PrintSimCfg  = 1'b0,
  parameter              ImplKey      = "none"
) ();
endmodule

`define IHP13_TC_SRAM_1024x32_TIEOFF \
    .A_BIST_CLK   (  1'b0 ), \
    .A_BIST_ADDR  ( 10'd0 ), \
    .A_BIST_DIN   ( 32'd0 ), \
    .A_BIST_BM    ( 32'd0 ), \
    .A_BIST_MEN   (  1'b0 ), \
    .A_BIST_WEN   (  1'b0 ), \
    .A_BIST_REN   (  1'b0 ), \
    .A_BIST_EN    (  1'b0 ), \
    .A_DLY        (  1'b0 )

`define IHP13_TC_SRAM_512x32_TIEOFF \
    .A_BIST_CLK   (  1'b0 ), \
    .A_BIST_ADDR  (  9'd0 ), \
    .A_BIST_DIN   ( 32'd0 ), \
    .A_BIST_BM    ( 32'd0 ), \
    .A_BIST_MEN   (  1'b0 ), \
    .A_BIST_WEN   (  1'b0 ), \
    .A_BIST_REN   (  1'b0 ), \
    .A_BIST_EN    (  1'b0 ), \
    .A_DLY        (  1'b0 )

`define IHP13_TC_SRAM_64x64_TIEOFF \
    .A_BIST_CLK   (  1'b0 ), \
    .A_BIST_ADDR  (  6'd0 ), \
    .A_BIST_DIN   ( 64'd0 ), \
    .A_BIST_BM    ( 64'd0 ), \
    .A_BIST_MEN   (  1'b0 ), \
    .A_BIST_WEN   (  1'b0 ), \
    .A_BIST_REN   (  1'b0 ), \
    .A_BIST_EN    (  1'b0 ), \
    .A_DLY        (  1'b0 )

module tc_sram #(
  parameter int unsigned NumWords     = 32'd1024,
  parameter int unsigned DataWidth    = 32'd128,
  parameter int unsigned ByteWidth    = 32'd8,
  parameter int unsigned NumPorts     = 32'd2,
  parameter int unsigned Latency      = 32'd1,
  parameter              SimInit      = "none",
  parameter bit          PrintSimCfg  = 1'b0,
  parameter              ImplKey      = "none",
  // DEPENDENT PARAMETERS, DO NOT OVERWRITE!
  parameter int unsigned AddrWidth = (NumWords > 32'd1) ? $clog2(NumWords) : 32'd1,
  parameter int unsigned BeWidth   = (DataWidth + ByteWidth - 32'd1) / ByteWidth,
  parameter type         addr_t    = logic [AddrWidth-1:0],
  parameter type         data_t    = logic [DataWidth-1:0],
  parameter type         be_t      = logic [BeWidth-1:0]
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  logic  [NumPorts-1:0] req_i,
  input  logic  [NumPorts-1:0] we_i,
  input  addr_t [NumPorts-1:0] addr_i,
  input  data_t [NumPorts-1:0] wdata_i,
  input  be_t   [NumPorts-1:0] be_i,
  output data_t [NumPorts-1:0] rdata_o
);

  localparam P1L1 = (NumPorts == 1 & Latency == 1);

  data_t [NumPorts-1:0] bm;

  for (genvar p = 0; p < NumPorts; ++p) begin : gen_bm_ports
      for (genvar b = 0; b < DataWidth; ++b) begin : gen_bm_bits
        assign bm[p][b] = be_i[p][b/ByteWidth];
      end
  end

  // Map onto one or more banked 1024x32 cuts
  if (NumWords % 1024 == 0 && DataWidth == 32 && P1L1) begin: gen_1024x32
    localparam int unsigned CutAddrWidth = 10;
    localparam int unsigned NumCuts      = NumWords / 1024;
    localparam int unsigned SelWidth     = (NumCuts > 1) ? $clog2(NumCuts) : 1;

    logic [NumCuts-1:0][DataWidth-1:0] cut_rdata;
    logic [SelWidth-1:0] sel_d, sel_q;

    if (NumCuts > 1) begin : gen_sel
      assign sel_d = addr_i[0][AddrWidth-1:CutAddrWidth];
      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)       sel_q <= '0;
        else if (req_i[0]) sel_q <= sel_d;
      end
    end else begin : gen_no_sel
      assign sel_d = '0;
      assign sel_q = '0;
    end

    assign rdata_o[0] = cut_rdata[sel_q];

    for (genvar c = 0; c < NumCuts; ++c) begin : gen_cuts
      logic men;
      assign men = req_i[0] & (sel_d == c);

      RM_IHPSG13_1P_1024x32_c2_bm_bist i_cut (
       .A_CLK   ( clk_i                       ),
       .A_ADDR  ( addr_i[0][CutAddrWidth-1:0] ),
       .A_BM    ( bm[0]                       ),
       .A_MEN   ( men                         ),
       .A_WEN   ( we_i[0]                     ),
       .A_REN   ( ~we_i[0]                    ),
       .A_DIN   ( wdata_i[0]                  ),
       .A_DOUT  ( cut_rdata[c]                ),
       `IHP13_TC_SRAM_1024x32_TIEOFF
      );
    end

  end else if (NumWords % 512 == 0 && DataWidth == 32 && P1L1) begin: gen_512x32
    localparam int unsigned CutAddrWidth = 9;
    localparam int unsigned NumCuts      = NumWords / 512;
    localparam int unsigned SelWidth     = (NumCuts > 1) ? $clog2(NumCuts) : 1;

    logic [NumCuts-1:0][DataWidth-1:0] cut_rdata;
    logic [SelWidth-1:0] sel_d, sel_q;

    if (NumCuts > 1) begin : gen_sel
      assign sel_d = addr_i[0][AddrWidth-1:CutAddrWidth];
      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)       sel_q <= '0;
        else if (req_i[0]) sel_q <= sel_d;
      end
    end else begin : gen_no_sel
      assign sel_d = '0;
      assign sel_q = '0;
    end

    assign rdata_o[0] = cut_rdata[sel_q];

    for (genvar c = 0; c < NumCuts; ++c) begin : gen_cuts
      logic men;
      assign men = req_i[0] & (sel_d == c);

      RM_IHPSG13_1P_512x32_c2_bm_bist i_cut (
       .A_CLK   ( clk_i                       ),
       .A_ADDR  ( addr_i[0][CutAddrWidth-1:0] ),
       .A_BM    ( bm[0]                       ),
       .A_MEN   ( men                         ),
       .A_WEN   ( we_i[0]                     ),
       .A_REN   ( ~we_i[0]                    ),
       .A_DIN   ( wdata_i[0]                  ),
       .A_DOUT  ( cut_rdata[c]                ),
       `IHP13_TC_SRAM_512x32_TIEOFF
      );
    end

  end else if (NumWords == 64 && DataWidth <= 64 && P1L1) begin: gen_64x64
    logic [63:0] cut_dout;

    RM_IHPSG13_1P_64x64_c2_bm_bist i_cut (
     .A_CLK   ( clk_i             ),
     .A_ADDR  ( addr_i[0]         ),
     .A_BM    ( 64'(bm[0])        ),
     .A_MEN   ( req_i[0]          ),
     .A_WEN   ( we_i[0]           ),
     .A_REN   ( ~we_i[0]          ),
     .A_DIN   ( 64'(wdata_i[0])   ),
     .A_DOUT  ( cut_dout          ),
     `IHP13_TC_SRAM_64x64_TIEOFF
    );

    assign rdata_o[0] = cut_dout[DataWidth-1:0];

  end else begin : gen_blackbox

  `ifdef SYNTHESIS
    tc_sram_blackbox #(
      .NumWords     ( NumWords    ),
      .DataWidth    ( DataWidth   ),
      .ByteWidth    ( ByteWidth   ),
      .NumPorts     ( NumPorts    ),
      .Latency      ( Latency     ),
      .SimInit      ( SimInit     ),
      .PrintSimCfg  ( PrintSimCfg ),
      .ImplKey      ( ImplKey     )
    ) i_sram_blackbox ();
  `endif

end

endmodule
