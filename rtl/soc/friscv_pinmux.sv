// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/

/*
 * Per-pad alternate-function multiplexer.
 *
 * One register per pad, PAD_SEL[p] at byte offset 4*p. Upper bits read as 0, writes ignored.
 * Reset default is AF0 for all pads. Data paths are combinatorial, no synchronization.
 */

module friscv_pinmux #(
    parameter int unsigned NumPads = 8,
    parameter int unsigned NumAfs  = 4,
    parameter logic [NumPads-1:0][NumAfs-1:0] AfInIdle = '0,
    parameter type reg_req_t = logic,
    parameter type reg_rsp_t = logic
) (
    input  logic clk_i,
    input  logic rst_ni,

    // Configuration interface
    input  reg_req_t reg_req_i,
    output reg_rsp_t reg_rsp_o,

    // Pad side
    input  logic [NumPads-1:0] pad_in_i,
    output logic [NumPads-1:0] pad_out_o,
    output logic [NumPads-1:0] pad_oe_o,

    // Function side
    input  logic [NumPads-1:0][NumAfs-1:0] func_out_i,
    output logic [NumPads-1:0][NumAfs-1:0] func_in_o,
    input  logic [NumPads-1:0][NumAfs-1:0] func_oe_i
);

localparam int unsigned SelWidth  = (NumAfs > 1) ? unsigned'($clog2(NumAfs)) : 1;
localparam int unsigned IdxWidth  = (NumAfs > 1) ? unsigned'($clog2(NumPads)) : 1;
localparam int unsigned DataWidth = $bits(reg_req_i.wdata);

// ============================================================
// Configuration registers
// ============================================================

logic [NumPads-1:0][SelWidth-1:0] sel_q;

logic [31:0]         word_idx;
logic                in_range;
logic [IdxWidth-1:0] idx;

assign word_idx = 32'(reg_req_i.addr) >> 2;
assign in_range = word_idx < NumPads;
assign idx      = word_idx[IdxWidth-1:0];

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        sel_q <= '0;
    end else if (reg_req_i.valid && reg_req_i.write && in_range && reg_req_i.wstrb[0]) begin
        sel_q[idx] <= reg_req_i.wdata[SelWidth-1:0];
    end
end

assign reg_rsp_o.ready = 1'b1;
assign reg_rsp_o.error = reg_req_i.valid && !in_range;
assign reg_rsp_o.rdata = (reg_req_i.valid && !reg_req_i.write && in_range) ? DataWidth'(sel_q[idx]) : '0;

// ============================================================
// Pad muxes
// ============================================================

for (genvar p = 0; p < NumPads; p++) begin : gen_pad
    assign pad_out_o[p] = func_out_i[p][sel_q[p]];
    assign pad_oe_o [p] = func_oe_i [p][sel_q[p]];

    for (genvar f = 0; f < NumAfs; f++) begin : gen_func
        assign func_in_o[p][f] = (sel_q[p] == f) ? pad_in_i[p] : AfInIdle[p][f];
    end
end

endmodule
