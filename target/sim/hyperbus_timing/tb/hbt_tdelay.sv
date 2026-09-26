// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Matej Jurasić <matej.jurasic@cappig.dev>

// Transport delay with rise/fall delays and an uncertainty window: an edge lands
// at a random point in [d, d + unc] and stable_o is low over the whole window.
// stable_i carries an upstream window through (fast edge in, slow edge + unc out).
module hbt_tdelay (
    input  logic in_i,
    input  logic stable_i,
    output logic out_o,
    output logic stable_o
);

real rise_ns = 0.0;
real fall_ns = 0.0;
real unc_ns  = 0.0;

int unsigned open_windows = 0;
logic        in_unstable  = 1'b0;

function automatic void set(real r, real f, real u = 0.0);
    rise_ns = r;
    fall_ns = f;
    unc_ns  = u;
endfunction

initial begin
    out_o    = in_i;
    stable_o = 1'b1;
end

// Of several input changes in one time step (zero-delay glitches, e.g. the DDR
// mux passing its stale q0) only the last is delivered; a glitch back to the
// committed value schedules nothing. The caller's window covers its width.
// Jitter can land a later edge first: then the earlier one is dropped, so a
// pulse narrower than the spread is swallowed and out_o ends on the last value.
int unsigned seq = 0;
int unsigned last_id = 0;
int unsigned landed_id = 0;
realtime     last_in = -1.0;
bit          cancelled [int unsigned];
logic        committed_val, committed_prev;
initial begin
    committed_val  = in_i;
    committed_prev = in_i;
end

function automatic bit superseded(int unsigned id);
    if (!cancelled.exists(id)) return 1'b0;
    cancelled.delete(id);
    return 1'b1;
endfunction

function automatic void land(int unsigned id, logic v);
    if (id < landed_id) return;
    landed_id = id;
    out_o     = v;
endfunction

always @(in_i) begin
    automatic logic        v   = in_i;
    automatic int unsigned id  = ++seq;
    automatic real         d   = v ? rise_ns : fall_ns;
    automatic real         u   = unc_ns;
    // strictly inside the window: Verilator 5.046 does not propagate a change made
    // after a zero delay through continuous assigns until the next event
    automatic real         jit = (u > 0.0) ? u * real'($urandom_range(1, 999)) / 1000.0 : 0.0;
    automatic realtime     t_out = $realtime + d + jit;
    if (last_in == $realtime && last_id != 0) begin
        cancelled[last_id] = 1'b1;
        committed_val = committed_prev;
    end
    last_in = $realtime;
    if (v === committed_val) begin
        last_id = 0;
    end else begin
        committed_prev = committed_val;
        committed_val  = v;
        last_id = id;
        if (u > 0.0) begin
            fork begin
                #(d);
                if (!superseded(id)) begin
                    open_windows++;
                    stable_o = 1'b0;
                    #(t_out - $realtime) land(id, v);
                    #(u - jit) open_windows--;
                    if (open_windows == 0 && !in_unstable) stable_o = 1'b1;
                end
            end join_none
        end else begin
            fork begin
                #(t_out - $realtime);
                if (!superseded(id)) land(id, v);
            end join_none
        end
    end
end

// An upstream window opens at the fastest delay and closes at the slowest; a
// close is dropped if the input became unstable again meanwhile
int unsigned stable_seq = 0;
always @(stable_i) begin
    automatic logic        s     = stable_i;
    automatic int unsigned id    = ++stable_seq;
    automatic real         d_min = (rise_ns < fall_ns) ? rise_ns : fall_ns;
    automatic real         d_max = ((rise_ns > fall_ns) ? rise_ns : fall_ns) + unc_ns;
    if (!s) begin
        fork begin
            #(d_min) in_unstable = 1'b1;
            stable_o = 1'b0;
        end join_none
    end else begin
        fork begin
            #(d_max);
            if (id == stable_seq) begin
                in_unstable = 1'b0;
                if (open_windows == 0) stable_o = 1'b1;
            end
        end join_none
    end
end

endmodule
