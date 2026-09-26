// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Matej Jurasić <matej.jurasic@cappig.dev>

// Setup/hold checker that records the worst slack. stable_i is low while any
// data bit may move. clk_ofs/data_ofs add path delay not in the waveform; hold
// uses the late clock (clk_ofs + clk_skew) and the early data (data_ofs_hold).
module hbt_shchk #(
    parameter string       Name  = "chk",
    parameter int unsigned W     = 1,
    parameter int unsigned Edges = 3,       // bit 0: posedge, bit 1: negedge
    parameter hbt_pkg::hbt_grp_e Grp = hbt_pkg::GrpInt
) (
    input logic         clk_i,
    input logic [W-1:0] data_i,
    input logic         stable_i,
    input logic         en_i
);

import hbt_pkg::*;

real setup_ns  = 0.0;
real hold_ns   = 0.0;
real clk_ofs   = 0.0;
real data_ofs  = 0.0;
real clk_skew  = 0.0;
real data_ofs_hold = 0.0;
bit  enabled   = 1'b1;

real         worst_setup = 1.0e9;
real         worst_hold  = 1.0e9;
int unsigned n_checked   = 0;
int unsigned n_setup_vio = 0;
int unsigned n_hold_vio  = 0;

// Waveform times; with data_ofs > clk_ofs a change before the edge can arrive
// after it, so the previous settle time is kept too
realtime t_settled      = -1.0e9;
realtime t_settled_prev = -1.0e9;
realtime t_moved        = -1.0e9;

bit      hold_pending = 1'b0;
realtime hold_edge    = 0.0;
bit      setup_pending = 1'b0;  // edge inside an uncertainty window: resolved when data settles
realtime setup_edge    = 0.0;

function automatic void set(real su, real ho, real cofs = 0.0, real dofs = 0.0,
                            real cskew = 0.0, real dofs_hold = -1.0e9);
    setup_ns      = su;
    hold_ns       = ho;
    clk_ofs       = cofs;
    data_ofs      = dofs;
    clk_skew      = cskew;
    data_ofs_hold = (dofs_hold < -1.0e8) ? dofs : dofs_hold;
endfunction

function automatic void resolve_hold(realtime t_move);
    real slack;
    if (!hold_pending) return;
    hold_pending = 1'b0;
    slack = (t_move + data_ofs_hold) - hold_edge - hold_ns;
    if (slack < worst_hold) worst_hold = slack;
    if (slack < 0.0) begin
        n_hold_vio++;
        if (n_hold_vio <= hbt_cfg.max_msgs)
            $display("[%0.3f ns] HOLD   %-22s slack %7.3f ns (req %.3f)",
                     $realtime, Name, slack, hold_ns);
    end
endfunction

// Data movement
always @(data_i or negedge stable_i) begin
    resolve_hold($realtime);
    t_moved = $realtime;
end
always @(data_i or posedge stable_i) begin
    if (stable_i) begin
        t_settled_prev = t_settled;
        t_settled      = $realtime;
        if (setup_pending) begin
            setup_pending = 1'b0;
            setup_result(setup_edge - (t_settled + data_ofs) - setup_ns, 1'b1);
        end
    end
end

function automatic void setup_result(real su, bit in_window);
    if (su < worst_setup) worst_setup = su;
    if (su < 0.0) begin
        n_setup_vio++;
        if (n_setup_vio <= hbt_cfg.max_msgs)
            $display("[%0.3f ns] SETUP  %-22s slack %7.3f ns (req %.3f)%s", $realtime, Name, su,
                     setup_ns, in_window ? " [edge inside data uncertainty window]" : "");
    end
endfunction

task automatic sample();
    realtime t_edge;
    if (!(en_i && enabled)) return;
    t_edge = $realtime + clk_ofs;
    // A pending hold with no data movement since resolves clean here
    if (hold_pending) begin
        real slack = ($realtime + clk_ofs) - hold_edge;  // at least a full phase
        hold_pending = 1'b0;
        if (slack < worst_hold) worst_hold = slack;
    end
    n_checked++;
    if (stable_i && (t_moved + data_ofs_hold) > t_edge + clk_skew) begin
        // The last change only arrives after this edge: it is this edge's hold,
        // and setup is against the change before it
        realtime h_edge = t_edge + clk_skew;
        real     slack  = (t_moved + data_ofs_hold) - h_edge - hold_ns;
        if (slack < worst_hold) worst_hold = slack;
        if (slack < 0.0) begin
            n_hold_vio++;
            if (n_hold_vio <= hbt_cfg.max_msgs)
                $display("[%0.3f ns] HOLD   %-22s slack %7.3f ns (req %.3f)",
                         $realtime, Name, slack, hold_ns);
        end
        setup_result(t_edge - (t_settled_prev + data_ofs) - setup_ns, 1'b0);
        return;
    end
    if (!stable_i) begin
        setup_pending = 1'b1;
        setup_edge    = t_edge;
    end else begin
        setup_result(t_edge - (t_settled + data_ofs) - setup_ns, 1'b0);
    end
    hold_pending = 1'b1;
    hold_edge    = t_edge + clk_skew;
endtask

if (Edges[0]) begin : gen_pos
    always @(posedge clk_i) sample();
end
if (Edges[1]) begin : gen_neg
    always @(negedge clk_i) sample();
end

function automatic void report(output hbt_chk_result_t r);
    r.name        = Name;
    r.grp         = Grp;
    r.n_checked   = n_checked;
    r.n_setup_vio = n_setup_vio;
    r.n_hold_vio  = n_hold_vio;
    r.worst_setup = worst_setup;
    r.worst_hold  = worst_hold;
endfunction

always @(hbt_report_req) if (hbt_report_req != 0) begin
    hbt_chk_result_t r;
    report(r);
    hbt_chk_results.push_back(r);
end

endmodule
