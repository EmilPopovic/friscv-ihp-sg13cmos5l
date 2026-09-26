// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Matej Jurasić <matej.jurasic@cappig.dev>

// Pads and board between the controller's core-side ports and the HyperRAM
// balls. Outbound: on-chip route + pad at the board load + trace. The TX delay
// line is already in hyper_ck_o, so CK and CS# add only what follows it.
// Inbound: trace + pad + route to the capture flops. DQ/RWDS are shared; the
// balls carry whoever drives (else the idle model) and overlaps count as contention.
module hbt_board #(
    parameter int unsigned NumChips = 2
) (
    input  logic [7:0]          c_dq_o,
    input  logic                c_dq_oe_o,
    output logic [7:0]          c_dq_i,
    output logic                c_dq_i_stable,
    input  logic                c_rwds_o,
    input  logic                c_rwds_oe_o,
    output logic                c_rwds_i,
    output logic                c_rwds_i_stable,
    input  logic                c_ck_o,
    input  logic [NumChips-1:0] c_cs_no,
    input  logic                c_reset_no,
    output logic                m_ck,
    output logic [NumChips-1:0] m_cs_n,
    output logic                m_reset_n,
    output logic [7:0]          m_dq,
    output logic                m_dq_stable,
    output logic                m_rwds,
    output logic                m_rwds_stable,
    input  logic [NumChips-1:0][7:0] m_dq_drv,
    input  logic [NumChips-1:0]      m_dq_oe,
    input  logic [NumChips-1:0]      m_dq_drv_stable,
    input  logic [NumChips-1:0]      m_rwds_drv,
    input  logic [NumChips-1:0]      m_rwds_oe
);

import hbt_pkg::*;

logic [7:0] dq_pad, dq_pad_st;
logic       rwds_pad, rwds_pad_st;
logic       dq_en, dq_en_st, rwds_en, rwds_en_st;
logic       ck_st, rst_st;
logic [NumChips-1:0] cs_st;

for (genvar i = 0; i < 8; i++) begin : gen_dq_out
    hbt_tdelay i_d (
        .in_i     ( c_dq_o[i]    ),
        .stable_i ( 1'b1         ),
        .out_o    ( dq_pad[i]    ),
        .stable_o ( dq_pad_st[i] )
    );
    // window up to the flop -> mux-data path: the stale q0 passes at a rising clock
    initial begin
        real dmin, dmax, f;
        #0;
        dmin = hbt_chip.dq_out_min;
        dmax = (hbt_chip.dq_data_max > hbt_chip.dq_out_max) ? hbt_chip.dq_data_max
                                                            : hbt_chip.dq_out_max;
        f    = flight(0);
        i_d.set(dmin + pad(PadIoOut, 1) + f, dmin + pad(PadIoOut, 0) + f, dmax - dmin);
    end
end

hbt_tdelay i_rwds_out (
    .in_i     ( c_rwds_o    ),
    .stable_i ( 1'b1        ),
    .out_o    ( rwds_pad    ),
    .stable_o ( rwds_pad_st )
);

hbt_tdelay i_dq_en (
    .in_i     ( c_dq_oe_o ),
    .stable_i ( 1'b1      ),
    .out_o    ( dq_en     ),
    .stable_o ( dq_en_st  )
);

hbt_tdelay i_rwds_en (
    .in_i     ( c_rwds_oe_o ),
    .stable_i ( 1'b1        ),
    .out_o    ( rwds_en     ),
    .stable_o ( rwds_en_st  )
);

hbt_tdelay i_ck (
    .in_i     ( c_ck_o ),
    .stable_i ( 1'b1   ),
    .out_o    ( m_ck   ),
    .stable_o ( ck_st  )
);

hbt_tdelay i_reset (
    .in_i     ( c_reset_no ),
    .stable_i ( 1'b1       ),
    .out_o    ( m_reset_n  ),
    .stable_o ( rst_st     )
);

for (genvar j = 0; j < NumChips; j++) begin : gen_cs
    hbt_tdelay i_d (
        .in_i     ( c_cs_no[j] ),
        .stable_i ( 1'b1       ),
        .out_o    ( m_cs_n[j]  ),
        .stable_o ( cs_st[j]   )
    );
    // clocked by the delayed clock: macro -> flop -> pad
    initial begin
        real f;
        #0;
        f = flight(1);
        i_d.set(hbt_chip.cs_out_min + pad(PadOut, 1) + f, hbt_chip.cs_out_min + pad(PadOut, 0) + f,
                hbt_chip.cs_out_max - hbt_chip.cs_out_min);
    end
end

logic [7:0] dq_in_st;
for (genvar i = 0; i < 8; i++) begin : gen_dq_in
    hbt_tdelay i_d (
        .in_i     ( m_dq[i]     ),
        .stable_i ( m_dq_stable ),
        .out_o    ( c_dq_i[i]   ),
        .stable_o ( dq_in_st[i] )
    );
    initial begin
        real f;
        #0;
        f = flight(0);
        i_d.set(f + pad(PadIoIn, 1) + hbt_chip.dq_in_min, f + pad(PadIoIn, 0) + hbt_chip.dq_in_min,
                hbt_chip.dq_in_max - hbt_chip.dq_in_min);
    end
end
assign c_dq_i_stable = &dq_in_st;

hbt_tdelay i_rwds_in (
    .in_i     ( m_rwds          ),
    .stable_i ( m_rwds_stable   ),
    .out_o    ( c_rwds_i        ),
    .stable_o ( c_rwds_i_stable )
);

// Trace delay; skew_pattern 0: random, 1: data late / clock early, 2: data early / clock late
function automatic real flight(bit is_clock);
    int unsigned pat = plus_int("skew_pattern", 0);
    real s;
    case (pat)
        1:       s = is_clock ? -1.0 : 1.0;
        2:       s = is_clock ? 1.0 : -1.0;
        default: s = real'($urandom_range(0, 2000)) / 1000.0 - 1.0;
    endcase
    return hbt_cfg.flight_ns + s * hbt_cfg.flight_skew_ns;
endfunction

initial begin
    real f, dmin, dmax;
    #0;
    dmin = hbt_chip.rwds_out_min;
    dmax = (hbt_chip.rwds_data_max > hbt_chip.rwds_out_max) ? hbt_chip.rwds_data_max
                                                            : hbt_chip.rwds_out_max;
    f = flight(0);
    i_rwds_out.set(dmin + pad(PadIoOut, 1) + f, dmin + pad(PadIoOut, 0) + f, dmax - dmin);
    f = flight(0);
    i_dq_en.set(hbt_chip.oe_min + pad(PadIoEn, 1) + f, hbt_chip.oe_min + pad(PadIoEn, 0) + f,
                hbt_chip.oe_max - hbt_chip.oe_min);
    i_rwds_en.set(hbt_chip.oe_min + pad(PadIoEn, 1) + f, hbt_chip.oe_min + pad(PadIoEn, 0) + f,
                  hbt_chip.oe_max - hbt_chip.oe_min);
    f = flight(1);
    i_ck.set(hbt_chip.ck_out + pad(PadOut, 1, 1) + f, hbt_chip.ck_out + pad(PadOut, 0, 1) + f);
    i_reset.set(hbt_chip.l_core + hbt_chip.ckq + pad(PadOut, 1),
                hbt_chip.l_core + hbt_chip.ckq + pad(PadOut, 0));
    // RWDS in: the route into the RX delay line is in the delay model
    f = flight(0);
    i_rwds_in.set(f + pad(PadIoIn, 1, 1), f + pad(PadIoIn, 0, 1));
end

// The controller drives from its earliest enable to its latest release
logic c_dq_drv, c_rwds_drv;
assign c_dq_drv   = dq_en   | ~dq_en_st;
assign c_rwds_drv = rwds_en | ~rwds_en_st;

logic [7:0] dq_idle = '0;
logic       rwds_idle = 1'b0;

int unsigned n_dq_contention = 0, n_rwds_contention = 0;
realtime     t_dq_cont_start, t_rwds_cont_start;
real         max_dq_contention = 0.0, max_rwds_contention = 0.0;

function automatic int unsigned count_drivers(logic c, logic [NumChips-1:0] m);
    return int'(c) + $countones(m);
endfunction

always_comb begin
    automatic int unsigned nd = count_drivers(c_dq_drv, m_dq_oe);
    m_dq        = dq_idle;
    m_dq_stable = 1'b0;
    if (c_dq_drv) begin
        m_dq        = dq_pad;
        m_dq_stable = &dq_pad_st & dq_en_st;
    end else begin
        for (int j = 0; j < NumChips; j++)
            if (m_dq_oe[j]) begin
                m_dq        = m_dq_drv[j];
                m_dq_stable = m_dq_drv_stable[j];
            end
    end
    if (nd > 1) m_dq_stable = 1'b0;
end

always_comb begin
    automatic int unsigned nd = count_drivers(c_rwds_drv, m_rwds_oe);
    m_rwds        = rwds_idle;
    m_rwds_stable = 1'b0;
    if (c_rwds_drv) begin
        m_rwds        = rwds_pad;
        m_rwds_stable = rwds_pad_st & rwds_en_st;
    end else begin
        for (int j = 0; j < NumChips; j++)
            if (m_rwds_oe[j]) begin
                m_rwds        = m_rwds_drv[j];
                m_rwds_stable = 1'b1;
            end
    end
    if (nd > 1) m_rwds_stable = 1'b0;
end

always @(m_dq or m_rwds) begin
    if (count_drivers(c_dq_drv, m_dq_oe) > 0)
        dq_idle = (hbt_cfg.bus_idle == BusKeeper) ? m_dq
                                                  : (hbt_cfg.bus_idle == BusPullup ? '1 : '0);
    if (count_drivers(c_rwds_drv, m_rwds_oe) > 0)
        rwds_idle = (hbt_cfg.bus_idle == BusKeeper) ? m_rwds : (hbt_cfg.bus_idle == BusPullup);
end
initial begin
    #0;
    if (hbt_cfg.bus_idle == BusPullup) begin dq_idle = '1; rwds_idle = 1'b1; end
end

bit dq_cont = 1'b0, rwds_cont = 1'b0;
always @(c_dq_drv or m_dq_oe) begin
    automatic bit now = count_drivers(c_dq_drv, m_dq_oe) > 1;
    if (now && !dq_cont) begin
        t_dq_cont_start = $realtime;
        n_dq_contention++;
    end else if (!now && dq_cont) begin
        automatic real d = $realtime - t_dq_cont_start;
        if (d > max_dq_contention) max_dq_contention = d;
        if (n_dq_contention <= hbt_cfg.max_msgs)
            $display("[%0.3f ns] CONTENTION DQ for %.3f ns (ctrl %b, mem %b)",
                     $realtime, d, c_dq_drv, m_dq_oe);
    end
    dq_cont = now;
end
always @(c_rwds_drv or m_rwds_oe) begin
    automatic bit now = count_drivers(c_rwds_drv, m_rwds_oe) > 1;
    if (now && !rwds_cont) begin
        t_rwds_cont_start = $realtime;
        n_rwds_contention++;
    end else if (!now && rwds_cont) begin
        automatic real d = $realtime - t_rwds_cont_start;
        if (d > max_rwds_contention) max_rwds_contention = d;
        if (n_rwds_contention <= hbt_cfg.max_msgs)
            $display("[%0.3f ns] CONTENTION RWDS for %.3f ns (ctrl %b, mem %b)",
                     $realtime, d, c_rwds_drv, m_rwds_oe);
    end
    rwds_cont = now;
end

always @(hbt_report_req) if (hbt_report_req != 0) begin
    hbt_bus_result_t r;
    r.n_dq     = n_dq_contention;
    r.n_rwds   = n_rwds_contention;
    r.max_dq   = max_dq_contention;
    r.max_rwds = max_rwds_contention;
    hbt_bus_results.push_back(r);
end

endmodule
