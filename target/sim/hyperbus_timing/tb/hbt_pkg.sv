// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Matej Jurasić <matej.jurasic@cappig.dev>

// Types, run-time config and lookups. System data comes from hbt_gen.svh
// (written by hbt). Times in ns; corners 0 fast, 1 typ, 2 slow.
package hbt_pkg;

localparam int unsigned CORNER_FAST = 0;
localparam int unsigned CORNER_TYP  = 1;
localparam int unsigned CORNER_SLOW = 2;

function automatic string corner_name(int unsigned c);
    case (c)
        CORNER_FAST: return "fast";
        CORNER_TYP:  return "typ";
        default:     return "slow";
    endcase
endfunction

// devices/hyperram.toml
typedef struct {
    string name;
    real   tck_min;
    real   tckhp_min;
    real   tcshi;
    real   trwr;
    real   tcss;
    real   tcsh;
    real   tdsv_max;
    real   tis;
    real   tih;
    real   tacc;
    real   tckd_min;
    real   tckd_max;
    real   tckdi_min;
    real   tckds_min;
    real   tckds_max;
    real   tdss;
    real   tdsz_max;
    real   toz_max;
    real   tcsm_max;
    real   tvcs;
    longint unsigned die_bytes;
    longint unsigned chip_bytes;
} hbt_mem_profile_t;

// On-chip paths per corner, from the clock root or a pad/macro pin; min/max
// over the bits of a bus and rise/fall
typedef struct {
    string src;
    // TX: clock root -> pad c2p
    real dq_out_min,   dq_out_max;    // via the DDR mux select (S -> X)
    real dq_data_max;                 // after the rising clock, when the DDR flops update
    real rwds_out_min, rwds_out_max;
    real rwds_data_max;
    real oe_min,       oe_max;        // DQ/RWDS output enable flops -> c2p_en
    real dl_tx_in;                    // clock root -> TX delay line clk_i
    real ck_out;                      // TX delay line clk_o -> CK pad c2p (through the clock gate)
    real cs_out_min,   cs_out_max;    // CS# flop clock (TX clk_o or clock root) -> CS pad c2p
    // RX: pad p2c -> register
    real rwds_in_dl;                  // RWDS pad p2c -> RX delay line clk_i
    real rx_icg;                      // RX delay line clk_o -> RX clock gate CLK
    real rx_pos_min,   rx_pos_max;    // RX delay line clk_o -> rising-edge capture flops CK
    real rx_neg_min,   rx_neg_max;    // RX delay line clk_o -> RX FIFO write flops CK (inverted)
    real dq_in_min,    dq_in_max;     // DQ pad p2c -> capture flop D (both edges)
    real rws_in;                      // RWDS pad p2c -> rwds_sample flop D
    // Clock-root latency to PHY control flops and their CK->Q
    real l_core;
    real ckq;
    // Internal clock-crossing paths into the shifted/strobe domains
    real cs_d_min,     cs_d_max;      // clock root -> CS# flop D
    real ckena_d_min,  ckena_d_max;   // clock root -> CK clock gate GATE
    real rxena_d_min,  rxena_d_max;   // clock root -> RX clock gate GATE
    // Library checks
    real ff_setup, ff_hold;
    real icg_setup, icg_hold;
} hbt_chip_delays_t;

// RWDS between CA and read data, which the datasheets leave open
typedef enum int unsigned {
    RwdsLowAfterCa    = 0, // drops to LOW at the end of CA, held LOW until data
    RwdsLowBeforeData = 1, // keeps the CA level until one clock before data
    RwdsHizAfterCa    = 2  // released after CA, driven LOW again one clock before data
} hbt_rwds_mode_e;

// Undriven DQ/RWDS
typedef enum int unsigned {
    BusKeeper   = 0,
    BusPulldown = 1,
    BusPullup   = 2
} hbt_bus_idle_e;

`include "hbt_gen.svh"

// Contents of a never-written word, so reads before writes check too; idx = phy * NumChips + chip
function automatic logic [15:0] init_word(int unsigned a, int unsigned idx);
    logic [31:0] h = (a ^ (idx << 28)) * 32'h9E37_79B1;
    return h[31:16] ^ h[15:0];
endfunction

typedef struct {
    int unsigned corner;
    real         tck_ns;        // clk_phy_i = clk_sys_i
    real         ck_ns;         // HyperBus CK (2 x tck_ns with the clk/2 generator)
    int unsigned tx_code;
    int unsigned rx_code;
    bit          keep_reset_taps;
    real         load_pf;
    real         flight_ns;
    real         flight_skew_ns;
    string       mem_part;
    real         mem_tckds;     // this device's CK->RWDS
    real         mem_tdsv;      // this device's CS#->RWDS valid
    real         mem_dq_skew;   // DQ vs RWDS, within +/- tDSS
    hbt_rwds_mode_e rwds_mode;
    hbt_bus_idle_e  bus_idle;
    int unsigned mem_latency;
    bit          mem_fixed_latency;
    int unsigned refresh_pct;   // chance of a refresh collision (variable latency)
    bit          program_cr0;
    int unsigned n_txn;
    int unsigned seed;
    int unsigned max_msgs;
    bit          verbose;
    real         jitter_ns;
    real         duty;          // clk high time, fraction of the period
    real         ocv;           // on-chip variation, fraction of each on-chip delay
    int unsigned ocv_pattern;   // 1: data late, clock early (setup); 2: the reverse (hold)
    int unsigned long_bursts;   // long AXI bursts per chip, before the random traffic
} hbt_cfg_t;

hbt_cfg_t          hbt_cfg;
hbt_mem_profile_t  hbt_mem;
hbt_chip_delays_t  hbt_chip;

function automatic real plus_real(string name, real dflt);
    real v;
    if ($value$plusargs({name, "=%f"}, v)) return v;
    return dflt;
endfunction

function automatic int unsigned plus_int(string name, int unsigned dflt);
    int unsigned v;
    if ($value$plusargs({name, "=%d"}, v)) return v;
    return dflt;
endfunction

// Right-aligned field (Verilator pads %<n>s on the right)
function automatic string rjust(string s, int unsigned w);
    while (s.len() < w) s = {" ", s};
    return s;
endfunction

function automatic string plus_str(string name, string dflt);
    string v;
    if ($value$plusargs({name, "=%s"}, v)) return v;
    return dflt;
endfunction

function automatic void load_cfg();
    string c;
    c = plus_str("corner", "typ");
    case (c)
        "fast":  hbt_cfg.corner = CORNER_FAST;
        "slow":  hbt_cfg.corner = CORNER_SLOW;
        default: hbt_cfg.corner = CORNER_TYP;
    endcase
    hbt_cfg.tck_ns            = plus_real("tck_ns", HBT_DEF_TCK_NS);
    hbt_cfg.ck_ns             = hbt_cfg.tck_ns * HBT_CK_DIV;
    hbt_cfg.keep_reset_taps   = !($test$plusargs("tx_code") || $test$plusargs("rx_code"));
    hbt_cfg.tx_code           = plus_int("tx_code", HBT_RST_TX_CODE);
    hbt_cfg.rx_code           = plus_int("rx_code", HBT_RST_RX_CODE);
    hbt_cfg.load_pf           = plus_real("load_pf", HBT_DEF_LOAD_PF);
    hbt_cfg.flight_ns         = plus_real("flight_ns", HBT_DEF_FLIGHT_NS);
    hbt_cfg.flight_skew_ns    = plus_real("flight_skew_ns", HBT_DEF_FLIGHT_SKEW_NS);
    hbt_cfg.mem_part          = plus_str("mem", HBT_DEF_MEM);
    hbt_mem                   = mem_profile(hbt_cfg.mem_part);
    hbt_cfg.mem_tckds         = plus_real("mem_tckds", hbt_mem.tckds_max);
    hbt_cfg.mem_tdsv          = plus_real("mem_tdsv", hbt_mem.tdsv_max);
    hbt_cfg.mem_dq_skew       = plus_real("mem_dq_skew", hbt_mem.tdss);
    hbt_cfg.rwds_mode         = hbt_rwds_mode_e'(plus_int("rwds_mode", RwdsLowAfterCa));
    hbt_cfg.bus_idle          = hbt_bus_idle_e'(plus_int("bus_idle", HBT_DEF_BUS_IDLE));
    hbt_cfg.mem_latency       = plus_int("mem_latency", HBT_DEF_LATENCY);
    hbt_cfg.mem_fixed_latency = plus_int("mem_fixed", HBT_DEF_FIXED_LATENCY);
    hbt_cfg.refresh_pct       = plus_int("refresh_pct", 25);
    hbt_cfg.program_cr0       = plus_int("program_cr0", HBT_DEF_PROGRAM_CR0);
    hbt_cfg.n_txn             = plus_int("n_txn", 400);
    hbt_cfg.seed              = plus_int("seed", 1);
    hbt_cfg.max_msgs          = plus_int("max_msgs", 5);
    hbt_cfg.verbose           = $test$plusargs("verbose");
    hbt_cfg.jitter_ns         = plus_real("jitter_ns", HBT_DEF_JITTER_NS);
    hbt_cfg.duty              = plus_real("duty", 0.5);
    hbt_cfg.ocv               = plus_real("ocv", 0.0);
    hbt_cfg.ocv_pattern       = plus_int("ocv_pattern", 0);
    hbt_cfg.long_bursts       = plus_int("long_bursts", 0);
    hbt_chip                  = derate(chip_delays(hbt_cfg.corner));
endfunction


// On-chip variation: scale for a clock-path or a data-path delay
function automatic real ocv(bit is_clock);
    case (hbt_cfg.ocv_pattern)
        1:       return is_clock ? 1.0 - hbt_cfg.ocv : 1.0 + hbt_cfg.ocv;
        2:       return is_clock ? 1.0 + hbt_cfg.ocv : 1.0 - hbt_cfg.ocv;
        default: return 1.0;
    endcase
endfunction

// Clock paths: into and out of the delay lines, the CK output, the core clock tree.
// Flop and clock-gate setup/hold are library values and stay.
function automatic hbt_chip_delays_t derate(hbt_chip_delays_t d);
    real c = ocv(1), x = ocv(0);
    d.dl_tx_in *= c; d.ck_out *= c; d.rwds_in_dl *= c; d.rx_icg *= c; d.l_core *= c;
    d.rx_pos_min *= c; d.rx_pos_max *= c; d.rx_neg_min *= c; d.rx_neg_max *= c;
    d.dq_out_min *= x; d.dq_out_max *= x; d.dq_data_max *= x;
    d.rwds_out_min *= x; d.rwds_out_max *= x; d.rwds_data_max *= x;
    d.oe_min *= x; d.oe_max *= x; d.cs_out_min *= x; d.cs_out_max *= x;
    d.dq_in_min *= x; d.dq_in_max *= x; d.rws_in *= x; d.ckq *= x;
    d.cs_d_min *= x; d.cs_d_max *= x; d.ckena_d_min *= x; d.ckena_d_max *= x;
    d.rxena_d_min *= x; d.rxena_d_max *= x;
    return d;
endfunction

// Delay line clk_i -> clk_o for the tap code at the macro's delay_i
function automatic real dline(int unsigned corner, int unsigned code, bit rise);
    if (code >= HBT_NUM_CODES) code = HBT_NUM_CODES - 1;
    return ocv(1) * (rise ? HBT_DLINE_RISE[corner][code] : HBT_DLINE_FALL[corner][code]);
endfunction

typedef enum int unsigned { PadOut, PadIoOut, PadIoIn, PadIoEn } hbt_pad_arc_e;

function automatic real pad_tab(hbt_pad_arc_e arc, int unsigned c, int unsigned l, bit rise);
    int unsigned e = rise ? 0 : 1;
    case (arc)
        PadOut:    return HBT_PAD_OUT[c][l][e];
        PadIoOut: return HBT_PAD_IO_OUT[c][l][e];
        PadIoIn:  return HBT_PAD_IO_IN[c][l][e];
        default:    return HBT_PAD_IO_EN[c][l][e];
    endcase
endfunction

// Pad delay of a clock or data net at the configured load
function automatic real pad(hbt_pad_arc_e arc, bit rise, bit is_clock = 1'b0);
    return ocv(is_clock) * pad_at_load(arc, rise);
endfunction

// Linear between characterised loads
function automatic real pad_at_load(hbt_pad_arc_e arc, bit rise);
    real ld = hbt_cfg.load_pf;
    int unsigned c = hbt_cfg.corner;
    if (ld <= HBT_LOADS_PF[0]) return pad_tab(arc, c, 0, rise);
    for (int unsigned i = 1; i < HBT_NUM_LOADS; i++) begin
        if (ld <= HBT_LOADS_PF[i]) begin
            real f = (ld - HBT_LOADS_PF[i-1]) / (HBT_LOADS_PF[i] - HBT_LOADS_PF[i-1]);
            return pad_tab(arc, c, i-1, rise) * (1.0 - f) + pad_tab(arc, c, i, rise) * f;
        end
    end
    return pad_tab(arc, c, HBT_NUM_LOADS-1, rise);
endfunction

typedef enum int unsigned { GrpMem, GrpRx, GrpRws, GrpInt } hbt_grp_e;

typedef struct {
    string       name;
    hbt_grp_e    grp;
    int unsigned n_checked;
    int unsigned n_setup_vio;
    int unsigned n_hold_vio;
    real         worst_setup;
    real         worst_hold;
} hbt_chk_result_t;

typedef struct {
    string       name;
    int unsigned n_vio;
    real         worst_tcss, worst_tcsh, worst_tcshi, worst_trwr, worst_tckhp, max_cs_low;
} hbt_dev_result_t;

typedef struct {
    int unsigned n_dq, n_rwds;
    real         max_dq, max_rwds;
} hbt_bus_result_t;

hbt_chk_result_t hbt_chk_results [$];
hbt_dev_result_t hbt_dev_results [$];
hbt_bus_result_t hbt_bus_results [$];
int unsigned     hbt_report_req = 0;

endpackage
