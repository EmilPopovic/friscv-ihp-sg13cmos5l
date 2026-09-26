// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Matej Jurasić <matej.jurasic@cappig.dev>

// HyperRAM model at its balls, timing from the part's profile (hbt_mem).
// CA on the first six CK edges, RWDS from tDSV after CS# (HIGH = 2x latency),
// read data edge-aligned with RWDS at tCKDS (DQ within +/- tDSS), write data
// center-aligned with RWDS as mask. Checks tIS/tIH, tCSS, tCSH, tCSHI, tRWR,
// tCSM, CK period and half period, and the first access after tVCS.
module hbt_hyperram #(
    parameter string       Name  = "hram",
    parameter int unsigned Index = 0
) (
    input  logic       reset_ni,
    input  logic       cs_ni,
    input  logic       ck_i,
    input  logic [7:0] dq_i,
    input  logic       dq_stable_i,
    input  logic       rwds_i,
    input  logic       rwds_stable_i,
    output logic [7:0] dq_o,
    output logic       dq_oe_o,
    output logic       dq_stable_o,
    output logic       rwds_o,
    output logic       rwds_oe_o
);

import hbt_pkg::*;

logic [15:0] mem [int unsigned];
logic [15:0] cr0 = 16'h8F1F;         // datasheet default: 6 clocks, fixed 2x latency, 32 B wrap
logic [15:0] cr1 = 16'hFFC1;

bit          active       = 1'b0;
bit          sampling     = 1'b0;    // next CK edge is sampled by this device (CA or write data)
int unsigned edge_idx     = 0;       // CK edges since CS# fell, first edge = 1
logic [47:0] ca           = '0;
bit          is_read, is_reg, is_linear;
int unsigned word_addr;
int unsigned burst_start;
int unsigned data_edge0;             // first data edge (rising), 0 until the CA is decoded
bit          lat2x;
logic [7:0]  byte_a;
logic        mask_a;
int unsigned words_done;

realtime t_cs_fall   = -1.0e9;
realtime t_cs_rise   = -1.0e9;
realtime t_ck_rise   = -1.0e9;
realtime t_ck_fall   = -1.0e9;
realtime t_reset_hi  = -1.0e9;
bit      first_rise  = 1'b1;
bit      seen_access = 1'b0;

int unsigned n_reads = 0, n_writes = 0, n_reg_writes = 0, n_reg_reads = 0, n_refresh = 0;
int unsigned n_vio   = 0;
real         worst_tcss   = 1.0e9;
real         worst_tcshi  = 1.0e9;
real         worst_trwr   = 1.0e9;
real         worst_tckhp  = 1.0e9;   // fraction of the period
real         worst_tcsh   = 1.0e9;
real         max_cs_low   = 0.0;

// Generation counter: a new CS# fall cancels drives still in flight
int unsigned gen = 0;

function automatic void violation(string what, real val, real req);
    n_vio++;
    if (n_vio <= hbt_cfg.max_msgs * 4)
        $display("[%0.3f ns] %s VIOLATION %s: %.3f ns (req %.3f ns)",
                 $realtime, Name, what, val, req);
endfunction

function automatic logic [15:0] init_word(int unsigned a);
    return hbt_pkg::init_word(a, Index);
endfunction

// Word addresses a and b in the same die; linear bursts may not cross a die boundary
function automatic bit same_die(int unsigned a, int unsigned b);
    return a / (hbt_mem.die_bytes / 2) == b / (hbt_mem.die_bytes / 2);
endfunction

function automatic logic [15:0] read_word(int unsigned a);
    if (mem.exists(a)) return mem[a];
    return init_word(a);
endfunction

function automatic logic [15:0] peek(int unsigned a);
    return read_word(a);
endfunction

function automatic int unsigned latency_clocks();
    case (cr0[7:4])
        4'b0000: return 5;
        4'b0001: return 6;
        4'b1110: return 3;
        4'b1111: return 4;
        4'b0010: return 7;
        default: return 6;
    endcase
endfunction

function automatic int unsigned wrap_words();
    case (cr0[1:0])
        2'b00:   return 64;
        2'b01:   return 32;
        2'b10:   return 8;
        default: return 16;
    endcase
endfunction

function automatic int unsigned burst_addr(int unsigned n);
    if (is_linear || is_reg) return word_addr + n;
    begin
        int unsigned w = wrap_words();
        int unsigned base = word_addr & ~(w - 1);
        return base + ((word_addr + n) & (w - 1));
    end
endfunction

logic sample_en;
assign sample_en = sampling;

hbt_shchk #(
    .Name  ( {Name, ".dq(tIS/tIH)"} ),
    .W     ( 8                      ),
    .Edges ( 3                      ),
    .Grp   ( GrpMem                 )
) i_chk_dq (
    .clk_i    ( ck_i        ),
    .data_i   ( dq_i        ),
    .stable_i ( dq_stable_i ),
    .en_i     ( sample_en   )
);

logic rwds_sample_en;
bit   rwds_is_mask = 1'b0;
assign rwds_sample_en = sampling && rwds_is_mask;

hbt_shchk #(
    .Name  ( {Name, ".rwds(tIS/tIH)"} ),
    .W     ( 1                        ),
    .Edges ( 3                        ),
    .Grp   ( GrpMem                   )
) i_chk_rwds (
    .clk_i    ( ck_i           ),
    .data_i   ( rwds_i         ),
    .stable_i ( rwds_stable_i  ),
    .en_i     ( rwds_sample_en )
);

initial begin
    #0;
    i_chk_dq.set(hbt_mem.tis, hbt_mem.tih);
    i_chk_rwds.set(hbt_mem.tis, hbt_mem.tih);
    dq_o        = '0;
    dq_oe_o     = 1'b0;
    dq_stable_o = 1'b1;
    rwds_o      = 1'b0;
    rwds_oe_o   = 1'b0;
end

task automatic drive_rwds_at(realtime delay, logic oe, logic val);
    int unsigned g = gen;
    fork begin
        #(delay);
        if (g == gen) begin
            rwds_oe_o = oe;
            rwds_o    = val;
        end
    end join_none
endtask

// One read byte: RWDS at +tCKDS, each DQ bit within +/- skew of it
task automatic launch_byte(logic [7:0] b, logic rwds_level);
    int unsigned g   = gen;
    real         r   = hbt_cfg.mem_tckds;
    real         sk  = hbt_cfg.mem_dq_skew;
    real         pre = (r - sk > 0.0) ? r - sk : 0.0;
    fork begin
        #(pre);
        if (g == gen) begin
            dq_stable_o = 1'b0;
            dq_oe_o     = 1'b1;
        end
    end join_none
    for (int i = 0; i < 8; i++) begin
        automatic int  bi = i;
        automatic real t  = r + sk * (real'($urandom_range(0, 2000)) / 1000.0 - 1.0);
        if (t < 0.0) t = 0.0;
        fork begin
            #(t);
            if (g == gen) dq_o[bi] = b[bi];
        end join_none
    end
    drive_rwds_at(r, 1'b1, rwds_level);
    fork begin
        #(r + sk);
        if (g == gen) dq_stable_o = 1'b1;
    end join_none
endtask

always @(posedge reset_ni) t_reset_hi = $realtime;

always @(negedge cs_ni) begin
    automatic real hi = $realtime - t_cs_rise;
    if (!reset_ni) violation("CS# asserted while RESET# low", 0.0, 0.0);
    if (!seen_access && ($realtime - t_reset_hi) < hbt_mem.tvcs)
        violation("first access before tVCS after reset", $realtime - t_reset_hi, hbt_mem.tvcs);
    seen_access = 1'b1;
    if (t_cs_rise > 0.0) begin
        if (hi < worst_tcshi) worst_tcshi = hi;
        if (hi < hbt_mem.tcshi) violation("tCSHI", hi, hbt_mem.tcshi);
    end
    if (ck_i) violation("CS# fell while CK high", 0.0, 0.0);
    gen++;
    active      = 1'b1;
    sampling    = 1'b1;
    rwds_is_mask = 1'b0;
    edge_idx    = 0;
    ca          = '0;
    data_edge0  = 0;
    words_done  = 0;
    first_rise  = 1'b1;
    t_cs_fall   = $realtime;
    // Refresh indication; fixed latency always asks for 2x
    lat2x = cr0[3] || ($urandom_range(0, 99) < hbt_cfg.refresh_pct);
    if (lat2x && !cr0[3]) n_refresh++;
    drive_rwds_at(hbt_cfg.mem_tdsv, 1'b1, lat2x);
end

always @(posedge cs_ni) begin
    automatic real low = $realtime - t_cs_fall;
    if (!active) begin
        t_cs_rise = $realtime;
    end else begin
        if (low > max_cs_low) max_cs_low = low;
        if (low > hbt_mem.tcsm_max) violation("tCSM", low, hbt_mem.tcsm_max);
        if (ck_i) violation("CS# rose while CK high", 0.0, 0.0);
        begin
            automatic real h = $realtime - t_ck_fall;
            if (h < worst_tcsh) worst_tcsh = h;
            if (h < hbt_mem.tcsh) violation("tCSH", h, hbt_mem.tcsh);
        end
        if (edge_idx < 6) violation("transaction ended inside CA", real'(edge_idx), 6.0);
        if (!is_read && !is_reg && data_edge0 != 0 && edge_idx >= data_edge0 &&
            (edge_idx - data_edge0) % 2 == 0)
            violation("write ended after byte A without byte B", 0.0, 0.0);
        active    = 1'b0;
        sampling  = 1'b0;
        t_cs_rise = $realtime;
        // Release after tOZ / tDSZ (worst case: latest). Bytes already launched
        // by the last CK edge still go out; only a new CS# fall cancels them.
        fork begin
            automatic int unsigned g = gen;
            #(hbt_mem.toz_max);
            if (g == gen) begin dq_oe_o = 1'b0; dq_stable_o = 1'b1; end
        end join_none
        fork begin
            automatic int unsigned g = gen;
            #(hbt_mem.tdsz_max);
            if (g == gen) rwds_oe_o = 1'b0;
        end join_none
    end
end

// Last full period while CK runs, else nominal (CK stops between and inside bursts)
function automatic real run_period(realtime t_prev_same_edge);
    real per = $realtime - t_prev_same_edge;
    return (per > 0.0 && per < 1.5 * hbt_cfg.ck_ns) ? per : hbt_cfg.ck_ns;
endfunction

always @(posedge ck_i) begin
    if (active && !first_rise && t_ck_fall > 0.0 && ($realtime - t_ck_fall) < hbt_cfg.ck_ns) begin
        automatic real per = run_period(t_ck_rise);
        automatic real lo  = $realtime - t_ck_fall;
        if (per < hbt_mem.tck_min && ($realtime - t_ck_rise) < 1.5 * hbt_cfg.ck_ns)
            violation("CK period", per, hbt_mem.tck_min);
        if (lo / per < worst_tckhp) worst_tckhp = lo / per;
        if (lo < hbt_mem.tckhp_min * per)
            violation("CK low half period", lo, hbt_mem.tckhp_min * per);
    end
    if (active && first_rise) begin
        automatic real su = $realtime - t_cs_fall;
        first_rise = 1'b0;
        if (su < worst_tcss) worst_tcss = su;
        if (su < hbt_mem.tcss) violation("tCSS", su, hbt_mem.tcss);
    end
    t_ck_rise = $realtime;
    if (active) ck_edge(1'b1);
end

always @(negedge ck_i) begin
    if (active && t_ck_rise > 0.0 && edge_idx > 0) begin
        automatic real hi  = $realtime - t_ck_rise;
        automatic real per = run_period(t_ck_fall);
        if (hi / per < worst_tckhp) worst_tckhp = hi / per;
        if (hi < hbt_mem.tckhp_min * per)
            violation("CK high half period", hi, hbt_mem.tckhp_min * per);
    end
    t_ck_fall = $realtime;
    if (active) ck_edge(1'b0);
end

task automatic ck_edge(bit rising);
    edge_idx++;
    if (edge_idx <= 6) begin
        ca = {ca[39:0], dq_i};
        if (edge_idx == 4) begin
            // tRWR: CS# high of the previous transaction to the end of CA1
            if (t_cs_rise > 0.0 && n_reads + n_writes + n_reg_writes + n_reg_reads > 0) begin
                real rwr = $realtime - t_cs_rise;
                if (rwr < worst_trwr) worst_trwr = rwr;
                if (rwr < hbt_mem.trwr) violation("tRWR", rwr, hbt_mem.trwr);
            end
        end
        if (edge_idx == 6) decode_ca();
        return;
    end
    if (data_edge0 == 0 || edge_idx < data_edge0) begin
        // Latency: schedule the read preamble one clock before data
        if (is_read && rising && edge_idx == data_edge0 - 2) begin
            if (hbt_cfg.rwds_mode != RwdsLowAfterCa) drive_rwds_at(hbt_cfg.mem_tckds, 1'b1, 1'b0);
        end
        // Next edge is the first data edge of a write: sample it
        if (!is_read && edge_idx + 1 == data_edge0) begin
            sampling     <= 1'b1;
            rwds_is_mask <= !is_reg;
        end
        return;
    end
    // Data phase
    begin
        int unsigned n  = (edge_idx - data_edge0) / 2;
        int unsigned wa = burst_addr(n);
        if (is_read) begin
            logic [15:0] w = is_reg ? reg_read(word_addr) : read_word(wa);
            if (rising) begin
                if (!is_reg && !same_die(wa, burst_start))
                    violation("linear burst crossed a die boundary", 0.0, 0.0);
                launch_byte(w[15:8], 1'b1);
            end else begin
                launch_byte(w[7:0], 1'b0);
                words_done++;
            end
        end else begin
            if (rising) begin
                byte_a = dq_i;
                mask_a = rwds_i;
            end else begin
                if (is_reg) begin
                    reg_write(word_addr, {byte_a, dq_i});
                    sampling <= 1'b0;
                end else begin
                    logic [15:0] old = read_word(wa);
                    logic [15:0] nw;
                    if (!same_die(wa, burst_start))
                        violation("linear burst crossed a die boundary", 0.0, 0.0);
                    nw[15:8] = mask_a ? old[15:8] : byte_a;
                    nw[7:0]  = rwds_i ? old[7:0]  : dq_i;
                    mem[wa]  = nw;
                    if (hbt_cfg.verbose)
                        $display("[%0.3f ns] %s WR  w%06h = %04h (mask %b%b)",
                                 $realtime, Name, wa, nw, mask_a, rwds_i);
                end
                words_done++;
            end
        end
    end
endtask

task automatic decode_ca();
    int unsigned lat;
    is_read    = ca[47];
    is_reg     = ca[46];
    is_linear  = ca[45];
    word_addr  = {ca[44:16], ca[2:0]};
    burst_start = word_addr;
    if (ca[15:3] != 0) violation("CA reserved bits not zero", real'(ca[15:3]), 0.0);
    lat = latency_clocks() * (lat2x ? 2 : 1);
    if (!is_read && is_reg) begin
        // Register write: data right after CA, RWDS not driven by the host (not a mask)
        data_edge0   = 7;
        sampling     <= 1'b1;
        rwds_is_mask <= 1'b0;
        n_reg_writes++;
    end else begin
        data_edge0 = 2 * (2 + lat) + 1;  // rising edge of clock 3 + lat
        sampling   <= 1'b0;
        if (is_read) begin
            if (is_reg) n_reg_reads++; else n_reads++;
        end else begin
            n_writes++;
        end
    end
    if (tacc_ok(lat) == 0)
        violation("initial latency shorter than tACC", real'(lat) * hbt_cfg.ck_ns, hbt_mem.tacc);
    // RWDS after the CA: reads keep driving it (LOW, or held until the preamble), writes release it
    if (is_read) begin
        case (hbt_cfg.rwds_mode)
            RwdsLowAfterCa:    drive_rwds_at(hbt_cfg.mem_tckds, 1'b1, 1'b0);
            RwdsHizAfterCa:    drive_rwds_at(hbt_cfg.mem_tckds, 1'b0, 1'b0);
            default: ;
        endcase
    end else begin
        drive_rwds_at(hbt_cfg.mem_tckds, 1'b0, 1'b0);
    end
    if (hbt_cfg.verbose)
        $display("[%0.3f ns] %s CA %s %s addr w%06h lat %0d%s",
                 $realtime, Name, is_read ? "RD" : "WR",
                 is_reg ? "REG" : "MEM", word_addr, lat, lat2x ? " (2x)" : "");
endtask

function automatic bit tacc_ok(int unsigned lat_clocks);
    return real'(latency_clocks()) * hbt_cfg.ck_ns >= hbt_mem.tacc;
endfunction

function automatic logic [15:0] reg_read(int unsigned a);
    case (a)
        32'h0000_0000: return 16'h0C81;  // ID0
        32'h0000_0001: return 16'h0001;  // ID1
        32'h0000_0800: return cr0;
        32'h0000_0801: return cr1;
        default:       return 16'h0000;
    endcase
endfunction

task automatic reg_write(int unsigned a, logic [15:0] v);
    case (a)
        32'h0000_0800: begin
            cr0 = v;
            $display("[%0.3f ns] %s CR0 <= %04h: latency %0d clocks, %s latency",
                     $realtime, Name, v,
                     latency_clocks(), v[3] ? "fixed 2x" : "variable");
        end
        32'h0000_0801: cr1 = v;
        default: violation("write to read-only register", real'(a), 0.0);
    endcase
endtask

always @(hbt_report_req) if (hbt_report_req != 0) begin
    hbt_dev_result_t r;
    r.name        = Name;
    r.n_vio       = n_vio;
    r.worst_tcss  = worst_tcss;
    r.worst_tcsh  = worst_tcsh;
    r.worst_tcshi = worst_tcshi;
    r.worst_trwr  = worst_trwr;
    r.worst_tckhp = worst_tckhp;
    r.max_cs_low  = max_cs_low;
    hbt_dev_results.push_back(r);
end

endmodule
