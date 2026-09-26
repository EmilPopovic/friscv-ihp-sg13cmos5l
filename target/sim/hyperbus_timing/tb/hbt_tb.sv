// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Matej Jurasić <matej.jurasic@cappig.dev>

// HyperBus timing simulation top: the PULP hyperbus (hbt_dut.svh) with a
// timed delay line, pads, board and HyperRAMs per PHY, driven by two AXI
// threads and checked against a shadow memory and timing checkers.
// Last line: "HBT_RESULT key=value ..." for `hbt sweep`.
`include "hbt_defines.svh"
`include "axi/typedef.svh"
`include "register_interface/typedef.svh"

module hbt_tb;

import hbt_pkg::*;

localparam int unsigned NumPhys  = HBT_NUM_PHYS;
localparam int unsigned NumChips = HBT_NUM_CHIPS;
localparam int unsigned DW       = HBT_AXI_DW;
localparam int unsigned SW       = DW / 8;              // bytes per beat
localparam int unsigned MaxSize  = $clog2(SW);
localparam int unsigned LineBeats = 64 / SW;            // 64 B cache line
localparam longint unsigned MemBase   = HBT_MEM_BASE;
localparam longint unsigned ChipSpace = HBT_CHIP_SPACE;

typedef logic [HBT_AXI_AW-1:0] axi_addr_t;
typedef logic [HBT_AXI_IW-1:0] axi_id_t;
typedef logic [DW-1:0]         axi_data_t;
typedef logic [SW-1:0]         axi_strb_t;
typedef logic [HBT_AXI_UW-1:0] axi_user_t;
`AXI_TYPEDEF_ALL(hbt_axi, axi_addr_t, axi_id_t, axi_data_t, axi_strb_t, axi_user_t)

typedef logic [HBT_REG_AW-1:0]   reg_addr_t;
typedef logic [HBT_REG_DW-1:0]   reg_data_t;
typedef logic [HBT_REG_DW/8-1:0] reg_strb_t;
`REG_BUS_TYPEDEF_ALL(hbt_reg, reg_addr_t, reg_data_t, reg_strb_t)

// Sweep builds shorten the PHY startup (still past tVCS)
`ifdef HBT_STARTUP_CYCLES
localparam int unsigned PhyStartupCycles = `HBT_STARTUP_CYCLES;
`else
localparam int unsigned PhyStartupCycles = HBT_PHY_STARTUP_CYCLES;
`endif

function automatic hyperbus_pkg::hyper_cfg_t hyper_rst_cfg();
    hyper_rst_cfg = hyperbus_pkg::gen_RstCfg(NumPhys, HBT_MIN_FREQ_MHZ);
    hyper_rst_cfg.address_mask_msb = 5'($clog2(ChipSpace));
    `HBT_RST_CFG_OVERRIDES(hyper_rst_cfg)
endfunction

logic clk = 1'b0;
logic rst_n = 1'b0;
bit   clk_run = 1'b0;

initial begin
    load_cfg();
    void'($urandom(hbt_cfg.seed));
    clk_run = 1'b1;
end

initial begin
    wait (clk_run);
    forever begin
        automatic real j = hbt_cfg.jitter_ns * (real'($urandom_range(0, 2000)) / 1000.0 - 1.0);
        // +duty is at the clk pad; its input buffer moves the edges by its rise/fall delays
        automatic real t    = hbt_cfg.tck_ns + j;
        automatic real skew = pad(PadIoIn, 1'b0, 1'b1) - pad(PadIoIn, 1'b1, 1'b1);
        #(t * (1.0 - hbt_cfg.duty) - skew) clk = 1'b1;
        #(t * hbt_cfg.duty + skew) clk = 1'b0;
    end
end

// +heartbeat_us=N
initial begin
    automatic int unsigned hb = plus_int("heartbeat_us", 0);
    if (hb != 0) forever begin
        #(real'(hb) * 1000.0);
        $display("[hbt] heartbeat %.1f us", $realtime / 1000.0);
    end
end

hbt_axi_req_t  axi_req;
hbt_axi_resp_t axi_rsp;
hbt_reg_req_t  reg_req;
hbt_reg_rsp_t  reg_rsp;

logic [NumPhys-1:0][NumChips-1:0] hyper_cs_no;
logic [NumPhys-1:0]               hyper_ck_o, hyper_ck_no;
logic [NumPhys-1:0]               hyper_rwds_o, hyper_rwds_i, hyper_rwds_oe_o;
logic [NumPhys-1:0][7:0]          hyper_dq_i, hyper_dq_o;
logic [NumPhys-1:0]               hyper_dq_oe_o, hyper_reset_no;

`include "hbt_dut.svh"

for (genvar p = 0; p < NumPhys; p++) begin : gen_phy
    logic                     m_ck, m_reset_n;
    logic [NumChips-1:0]      m_cs_n;
    logic [7:0]               m_dq;
    logic                     m_dq_stable, m_rwds, m_rwds_stable;
    logic [NumChips-1:0][7:0] m_dq_drv;
    logic [NumChips-1:0]      m_dq_oe, m_dq_drv_stable, m_rwds_drv, m_rwds_oe;
    logic                     dq_i_stable, rwds_i_stable;
    logic [7:0]               dq_o;
    logic [7:0]               dq_i;
    logic                     rwds_i;

    assign dq_o = hyper_dq_o[p];
    assign hyper_dq_i[p]   = dq_i;
    assign hyper_rwds_i[p] = rwds_i;

    hbt_board #(
        .NumChips ( NumChips )
    ) i_board (
        .c_dq_o          ( dq_o               ),
        .c_dq_oe_o       ( hyper_dq_oe_o[p]   ),
        .c_dq_i          ( dq_i               ),
        .c_dq_i_stable   ( dq_i_stable        ),
        .c_rwds_o        ( hyper_rwds_o[p]    ),
        .c_rwds_oe_o     ( hyper_rwds_oe_o[p] ),
        .c_rwds_i        ( rwds_i             ),
        .c_rwds_i_stable ( rwds_i_stable      ),
        .c_ck_o          ( hyper_ck_o[p]      ),
        .c_cs_no         ( hyper_cs_no[p]     ),
        .c_reset_no      ( hyper_reset_no[p]  ),
        .m_ck,
        .m_cs_n,
        .m_reset_n,
        .m_dq,
        .m_dq_stable,
        .m_rwds,
        .m_rwds_stable,
        .m_dq_drv,
        .m_dq_oe,
        .m_dq_drv_stable,
        .m_rwds_drv,
        .m_rwds_oe
    );

    for (genvar j = 0; j < NumChips; j++) begin : gen_mem
        hbt_hyperram #(
            .Name  ( $sformatf("phy%0d.hram%0d", p, j) ),
            .Index ( p * NumChips + j                  )
        ) i_mem (
            .reset_ni      ( m_reset_n          ),
            .cs_ni         ( m_cs_n[j]          ),
            .ck_i          ( m_ck               ),
            .dq_i          ( m_dq               ),
            .dq_stable_i   ( m_dq_stable        ),
            .rwds_i        ( m_rwds             ),
            .rwds_stable_i ( m_rwds_stable      ),
            .dq_o          ( m_dq_drv[j]        ),
            .dq_oe_o       ( m_dq_oe[j]         ),
            .dq_stable_o   ( m_dq_drv_stable[j] ),
            .rwds_o        ( m_rwds_drv[j]      ),
            .rwds_oe_o     ( m_rwds_oe[j]       )
        );
    end

    // Controller-side checks; RX only while read data is expected
    logic rx_expected;
    assign rx_expected = `HBT_PHY(p).state_q == hyperbus_pkg::Read ||
                         `HBT_PHY(p).r_outstand_q != '0;

    // Rising RWDS: DQ -> rx_rwds_fifo_in[15:8]
    hbt_shchk #(
        .Name  ( $sformatf("phy%0d.rx_capture_rise", p) ),
        .W     ( 8                                      ),
        .Edges ( 1                                      ),
        .Grp   ( GrpRx                                  )
    ) i_chk_rx_rise (
        .clk_i    ( `HBT_PHY(p).i_trx.rx_rwds_clk ),
        .data_i   ( dq_i                          ),
        .stable_i ( dq_i_stable                   ),
        .en_i     ( rx_expected                   )
    );

    // Falling RWDS: {fifo_in[15:8], DQ} -> RX CDC FIFO (inverted clock). The FIFO only takes
    // it after the first rising edge sets its valid, so a falling preamble edge is harmless.
    hbt_shchk #(
        .Name  ( $sformatf("phy%0d.rx_capture_fall", p) ),
        .W     ( 8                                      ),
        .Edges ( 2                                      ),
        .Grp   ( GrpRx                                  )
    ) i_chk_rx_fall (
        .clk_i    ( `HBT_PHY(p).i_trx.rx_rwds_clk                       ),
        .data_i   ( dq_i                                                ),
        .stable_i ( dq_i_stable                                         ),
        .en_i     ( rx_expected && `HBT_PHY(p).i_trx.rx_rwds_fifo_valid )
    );

    // RWDS latency sample, end of SendCA with timer 1
    logic rws_en;
    assign rws_en = `HBT_PHY(p).i_trx.rwds_sample_ena_i && `HBT_PHY(p).timer_q == 1 &&
                    `HBT_PHY(p).state_q == hyperbus_pkg::SendCA;
    hbt_shchk #(
        .Name  ( $sformatf("phy%0d.rwds_latency_sample", p) ),
        .W     ( 1                                          ),
        .Edges ( 1                                          ),
        .Grp   ( GrpRws                                     )
    ) i_chk_rws (
        .clk_i    ( clk           ),
        .data_i   ( rwds_i        ),
        .stable_i ( rwds_i_stable ),
        .en_i     ( rws_en        )
    );

    // RX clock gate enable against the delayed RWDS at the gate
    hbt_shchk #(
        .Name  ( $sformatf("phy%0d.rx_gate_enable", p) ),
        .W     ( 1                                     ),
        .Edges ( 1                                     ),
        .Grp   ( GrpInt                                )
    ) i_chk_rx_gate (
        .clk_i    ( `HBT_PHY(p).i_trx.rx_rwds_90      ),
        .data_i   ( `HBT_PHY(p).i_trx.rx_rwds_clk_ena ),
        .stable_i ( 1'b1                              ),
        .en_i     ( 1'b1                              )
    );
`ifdef HBT_TX_DELAYED
`ifndef HBT_CS_CORE_FALL

    // CS# flop on the TX 90-degree clock (on the core clock it is a plain STA path)
    logic [NumChips:0] cs_d;
    assign cs_d = {`HBT_PHY(p).i_trx.cs_ena_i, `HBT_PHY(p).i_trx.cs_i};
    hbt_shchk #(
        .Name  ( $sformatf("phy%0d.cs_flop_tx90", p) ),
        .W     ( NumChips + 1                        ),
        .Edges ( 1                                   ),
        .Grp   ( GrpInt                              )
    ) i_chk_cs (
        .clk_i    ( `HBT_PHY(p).i_trx.tx_clk_90 ),
        .data_i   ( cs_d                        ),
        .stable_i ( 1'b1                        ),
        .en_i     ( 1'b1                        )
    );
`endif

    // CK output clock gate enable against the TX 90-degree clock
    hbt_shchk #(
        .Name  ( $sformatf("phy%0d.ck_gate_enable", p) ),
        .W     ( 1                                     ),
        .Edges ( 1                                     ),
        .Grp   ( GrpInt                                )
    ) i_chk_ck_gate (
        .clk_i    ( `HBT_PHY(p).i_trx.tx_clk_90    ),
        .data_i   ( `HBT_PHY(p).i_trx.tx_clk_ena_q ),
        .stable_i ( 1'b1                           ),
        .en_i     ( 1'b1                           )
    );
`endif

    initial begin
        #0;
        i_chk_rx_rise.set(hbt_chip.ff_setup, hbt_chip.ff_hold, 0.0, 0.0,
                          hbt_chip.rx_pos_max - hbt_chip.rx_pos_min);
        i_chk_rx_fall.set(hbt_chip.ff_setup, hbt_chip.ff_hold,
                          hbt_chip.rx_neg_min - hbt_chip.rx_pos_min, 0.0,
                          hbt_chip.rx_neg_max - hbt_chip.rx_neg_min);
        i_chk_rws.set(hbt_chip.ff_setup, hbt_chip.ff_hold, hbt_chip.l_core, hbt_chip.rws_in);
        // rx_rwds_90 already includes the full tree; the gate sits before it
        i_chk_rx_gate.set(hbt_chip.icg_setup, hbt_chip.icg_hold,
                          hbt_chip.rx_icg - hbt_chip.rx_pos_min,
                          hbt_chip.rxena_d_max, 0.0, hbt_chip.rxena_d_min);
`ifdef HBT_TX_DELAYED
`ifndef HBT_CS_CORE_FALL
        i_chk_cs.set(hbt_chip.ff_setup, hbt_chip.ff_hold, 0.0, hbt_chip.cs_d_max, 0.0,
                     hbt_chip.cs_d_min);
`endif
        i_chk_ck_gate.set(hbt_chip.icg_setup, hbt_chip.icg_hold, 0.0, hbt_chip.ckena_d_max, 0.0,
                          hbt_chip.ckena_d_min);
`endif
    end

    // +trace_bus=<n>: print the pins around the first n CS# assertions (PHY 0);
    // +trace_from_ns / +trace_to_ns: print them over a time window
    if (p == 0) begin : gen_trace
        int unsigned trace_left = 0;
        real         trace_from = -1.0, trace_to = -1.0;
        initial begin
            #0;
            trace_from = plus_real("trace_from_ns", -1.0);
            trace_to   = plus_real("trace_to_ns", trace_from < 0.0 ? -1.0 : 1.0e18);
            wait (`HBT_PHY(p).state_q != hyperbus_pkg::Startup);
            trace_left = plus_int("trace_bus", 0);
        end
        always @(dq_o or hyper_dq_oe_o[p] or hyper_ck_o[p] or hyper_cs_no[p]
                 or m_dq or m_dq_stable or m_ck or m_cs_n or m_rwds or dq_i or dq_i_stable or rwds_i
                 or `HBT_PHY(p).state_q or `HBT_PHY(p).i_trx.rx_rwds_clk_ena
                 or `HBT_PHY(p).i_trx.rx_rwds_90 or `HBT_PHY(p).i_trx.rx_rwds_clk) begin
            automatic bit in_txn = hyper_cs_no[p] != '1 || m_cs_n != '1 ||
                                   `HBT_PHY(p).i_trx.rx_rwds_clk_ena;
            automatic bit in_window = $realtime >= trace_from && $realtime <= trace_to;
            if ((trace_left > 0 && in_txn) || in_window) begin
                $write("%12.3f  core: cs %b ck %b dq %02h oe %b st %0d", $realtime, hyper_cs_no[p],
                       hyper_ck_o[p], dq_o, hyper_dq_oe_o[p], `HBT_PHY(p).state_q);
                $write(" | balls: cs %b ck %b dq %02h/%b rwds %b drv c%b m%b",
                       m_cs_n, m_ck, m_dq, m_dq_stable, m_rwds, i_board.c_dq_drv, m_dq_oe);
                $display(" | rx: rwds %b en %b rwds90 %b gclk %b val %b dq_i %02h/%b",
                         rwds_i, `HBT_PHY(p).i_trx.rx_rwds_clk_ena, `HBT_PHY(p).i_trx.rx_rwds_90,
                         `HBT_PHY(p).i_trx.rx_rwds_clk, `HBT_PHY(p).i_trx.rx_rwds_fifo_valid,
                         dq_i, dq_i_stable);
            end
        end
        logic all_cs_hi;
        assign all_cs_hi = &m_cs_n;
        always @(posedge all_cs_hi) if (trace_left > 0) trace_left--;
    end
end

initial begin
    reg_req = '0;
    axi_req = '0;
end

localparam real TxnTimeoutNs = 20000.0;
int unsigned n_hang = 0;

// Any bus handshake that never completes ends the run as a hang
int unsigned n_inflight = 0;
realtime     t_progress = 0.0;
string       last_op = "";
function automatic void op_start(string op);
    n_inflight++;
    last_op    = op;
    t_progress = $realtime;
endfunction
function automatic void op_done();
    n_inflight--;
    t_progress = $realtime;
endfunction
initial begin
    wait (clk_run);
    forever begin
        #1000.0;
        if (n_inflight > 0 && $realtime - t_progress > 2 * TxnTimeoutNs) begin
            n_hang++;
            $display("[%0.3f ns] HANG   no bus progress for %.1f us (last started: %s)", $realtime,
                     ($realtime - t_progress) / 1000.0, last_op);
            finish_report();
        end
    end
end

task automatic reg_write(int unsigned idx, logic [31:0] data);
    op_start($sformatf("register write %0d", idx));
    @(posedge clk); #1;
    reg_req.addr  = HBT_REG_BASE + (idx << 2);
    reg_req.write = 1'b1;
    reg_req.wdata = data;
    reg_req.wstrb = '1;
    reg_req.valid = 1'b1;
    do @(posedge clk); while (!reg_rsp.ready);
    if (reg_rsp.error) $error("reg write %0d failed", idx);
    #1 reg_req = '0;
    op_done();
endtask

task automatic reg_read(int unsigned idx, output logic [31:0] data);
    op_start($sformatf("register read %0d", idx));
    @(posedge clk); #1;
    reg_req.addr  = HBT_REG_BASE + (idx << 2);
    reg_req.write = 1'b0;
    reg_req.valid = 1'b1;
    do @(posedge clk); while (!reg_rsp.ready);
    data = reg_rsp.rdata;
    #1 reg_req = '0;
    op_done();
endtask

bit aw_lock = 1'b0, ar_lock = 1'b0;
axi_data_t   r_q [2][$];
logic [1:0]  r_resp_q [2][$];
logic [1:0]  b_q [2][$];
int unsigned n_axi_err = 0;

always @(posedge clk) begin
    if (axi_rsp.r_valid && axi_req.r_ready) begin
        r_q[axi_rsp.r.id].push_back(axi_rsp.r.data);
        r_resp_q[axi_rsp.r.id].push_back(axi_rsp.r.resp);
    end
    if (axi_rsp.b_valid && axi_req.b_ready) b_q[axi_rsp.b.id].push_back(axi_rsp.b.resp);
end
initial begin
    #0;
    axi_req.r_ready = 1'b1;
    axi_req.b_ready = 1'b1;
end

task automatic axi_write(int unsigned id, axi_addr_t addr, int unsigned len, logic [2:0] size,
                         axi_data_t data [], axi_strb_t strb []);
    realtime t0;
    op_start($sformatf("AXI write id %0d addr %08h", id, addr));
    while (aw_lock) @(posedge clk);
    aw_lock = 1'b1;
    @(posedge clk); #1;
    axi_req.aw        = '0;
    axi_req.aw.id     = id;
    axi_req.aw.addr   = addr;
    axi_req.aw.len    = len - 1;
    axi_req.aw.size   = size;
    axi_req.aw.burst  = axi_pkg::BURST_INCR;
    axi_req.aw.cache  = 4'b0010;
    axi_req.aw_valid  = 1'b1;
    do @(posedge clk); while (!axi_rsp.aw_ready);
    #1 axi_req.aw_valid = 1'b0;
    for (int unsigned i = 0; i < len; i++) begin
        axi_req.w.data  = data[i];
        axi_req.w.strb  = strb[i];
        axi_req.w.last  = (i == len - 1);
        axi_req.w_valid = 1'b1;
        do @(posedge clk); while (!axi_rsp.w_ready);
        #1;
    end
    axi_req.w_valid = 1'b0;
    aw_lock = 1'b0;
    t0 = $realtime;
    while (b_q[id].size() == 0) begin
        @(posedge clk);
        if ($realtime - t0 > TxnTimeoutNs) begin
            n_hang++;
            $display("[%0.3f ns] HANG   write id %0d addr %08h: no B response",
                     $realtime, id, addr);
            finish_report();
        end
    end
    if (b_q[id].pop_front() != axi_pkg::RESP_OKAY) n_axi_err++;
    op_done();
endtask

task automatic axi_read(int unsigned id, axi_addr_t addr, int unsigned len, logic [2:0] size,
                        output axi_data_t data []);
    realtime t0;
    op_start($sformatf("AXI read id %0d addr %08h", id, addr));
    while (ar_lock) @(posedge clk);
    ar_lock = 1'b1;
    @(posedge clk); #1;
    axi_req.ar        = '0;
    axi_req.ar.id     = id;
    axi_req.ar.addr   = addr;
    axi_req.ar.len    = len - 1;
    axi_req.ar.size   = size;
    axi_req.ar.burst  = axi_pkg::BURST_INCR;
    axi_req.ar.cache  = 4'b0010;
    axi_req.ar_valid  = 1'b1;
    do @(posedge clk); while (!axi_rsp.ar_ready);
    #1 axi_req.ar_valid = 1'b0;
    ar_lock = 1'b0;
    data = new[len];
    t0 = $realtime;
    for (int unsigned i = 0; i < len; i++) begin
        while (r_q[id].size() == 0) begin
            @(posedge clk);
            if ($realtime - t0 > TxnTimeoutNs) begin
                n_hang++;
                $display("[%0.3f ns] HANG   read id %0d addr %08h: %0d of %0d beats", $realtime, id,
                         addr, i, len);
                finish_report();
            end
        end
        data[i] = r_q[id].pop_front();
        if (r_resp_q[id].pop_front() != axi_pkg::RESP_OKAY) n_axi_err++;
        t_progress = $realtime;
    end
    op_done();
endtask

logic [7:0] shadow [longint unsigned];
int unsigned n_mismatch = 0, n_bytes_checked = 0, n_reads = 0, n_writes = 0;

// Never-written byte at an AXI address. PHYs interleave per halfword; the
// odd byte is bits [15:8] (first on the bus).
function automatic logic [7:0] mem_byte(axi_addr_t addr);
    longint unsigned off  = addr - MemBase;
    int unsigned     chip = off / ChipSpace;
    longint unsigned co   = off % ChipSpace;
    int unsigned     phy  = (co >> 1) % NumPhys;
    int unsigned     wofs = co / (2 * NumPhys);
    logic [15:0]     w;
    if (shadow.exists(addr)) return shadow[addr];
    w = init_word(wofs, phy * NumChips + chip);
    return co[0] ? w[15:8] : w[7:0];
endfunction

function automatic void check_read(string what, axi_addr_t addr, int unsigned len, logic [2:0] size,
                                   axi_data_t data []);
    for (int unsigned i = 0; i < len; i++) begin
        axi_addr_t beat_addr = addr + i * (1 << size);
        for (int unsigned b = 0; b < (1 << size); b++) begin
            axi_addr_t   a    = beat_addr + b;
            int unsigned lane = a % SW;
            logic [7:0]  got  = data[i][8*lane +: 8];
            logic [7:0]  exp  = mem_byte(a);
            n_bytes_checked++;
            if (got !== exp) begin
                n_mismatch++;
                if (n_mismatch <= hbt_cfg.max_msgs * 2)
                    $display("[%0.3f ns] DATA   %s %08h: got %02h, expected %02h",
                             $realtime, what, a, got, exp);
            end
        end
    end
endfunction

function automatic void shadow_write(axi_addr_t addr, int unsigned len, logic [2:0] size,
                                     axi_data_t data [], axi_strb_t strb []);
    for (int unsigned i = 0; i < len; i++) begin
        axi_addr_t beat_addr = (addr + i * (1 << size)) & ~axi_addr_t'(SW - 1);
        for (int unsigned lane = 0; lane < SW; lane++)
            if (strb[i][lane]) shadow[beat_addr + lane] = data[i][8*lane +: 8];
    end
endfunction

// Thread 0: CPU-like mix, lower half of each chip. Thread 1: line reads, upper half.
function automatic axi_addr_t rand_addr(int unsigned thread, int unsigned align);
    int unsigned chip = $urandom_range(0, NumChips - 1);
    longint unsigned half = ChipSpace / 2;
    int unsigned off  = $urandom_range(0, 16383) & ~(align - 1);
    return MemBase + chip * ChipSpace + thread * half + off;
endfunction

function automatic axi_data_t rand_data();
    axi_data_t d;
    for (int unsigned i = 0; i < DW / 32; i++) d[32*i +: 32] = $urandom();
    return d;
endfunction

task automatic do_write(int unsigned id, axi_addr_t addr, int unsigned len, logic [2:0] size,
                        bit partial);
    axi_data_t data [];
    axi_strb_t strb [];
    data = new[len];
    strb = new[len];
    for (int unsigned i = 0; i < len; i++) begin
        axi_addr_t   ba = addr + i * (1 << size);
        axi_strb_t   m  = axi_strb_t'((1 << (1 << size)) - 1);
        data[i] = rand_data();
        strb[i] = m << (ba % SW & ~((1 << size) - 1));
        if (partial) begin
            axi_strb_t r;
            do r = axi_strb_t'({$urandom(), $urandom()}); while ((r & strb[i]) == '0);
            strb[i] &= r;
        end
    end
    axi_write(id, addr, len, size, data, strb);
    shadow_write(addr, len, size, data, strb);
    n_writes++;
endtask

task automatic do_read(int unsigned id, string what, axi_addr_t addr, int unsigned len,
                       logic [2:0] size);
    axi_data_t data [];
    axi_read(id, addr, len, size, data);
    check_read(what, addr, len, size, data);
    n_reads++;
endtask

task automatic thread_mix(int unsigned n);
    for (int unsigned t = 0; t < n; t++) begin
        int unsigned kind = $urandom_range(0, 99);
        if (kind < 30) begin
            axi_addr_t a = rand_addr(0, 64);
            do_write(0, a, LineBeats, MaxSize, 1'b0);           // line writeback
            if ($urandom_range(0, 1)) do_read(0, "line-after-write", a, LineBeats, MaxSize);
        end else if (kind < 55) begin
            do_read(0, "line", rand_addr(0, 64), LineBeats, MaxSize);
        end else if (kind < 70) begin
            do_write(0, rand_addr(0, SW), 1, MaxSize, 1'b1);     // full beat, random strobes
        end else if (kind < 78) begin
            do_write(0, rand_addr(0, 2), 1, 3'd1, 1'b0);        // halfword
        end else if (kind < 86) begin
            do_write(0, rand_addr(0, 1), 1, 3'd0, 1'b0);        // byte
        end else if (kind < 94) begin
            do_read(0, "word", rand_addr(0, 4), 1, 3'd2);
        end else begin
            axi_addr_t a = rand_addr(0, 1);
            do_read(0, "byte", a, 1, 3'd0);
        end
    end
endtask

task automatic thread_stream(int unsigned n);
    axi_addr_t a = rand_addr(1, 64);
    for (int unsigned t = 0; t < n; t++) begin
        if ($urandom_range(0, 9) == 0) begin
            a = rand_addr(1, 64);
            do_write(1, a, LineBeats, MaxSize, 1'b0);
        end
        do_read(1, "stream", a, LineBeats, MaxSize);
        a = a + 64;
    end
endtask

// Bursts longer than t_burst_max, which the controller splits (tCSM); 256 B each
task automatic long_bursts(int unsigned n);
    for (int unsigned i = 0; i < n; i++)
        for (int unsigned c = 0; c < NumChips; c++) begin
            axi_addr_t a = MemBase + c * ChipSpace + 32'h8000 + i * 256;
            do_write(0, a, 256 / SW, MaxSize, 1'b0);
            do_read(0, "long", a, 256 / SW, MaxSize);
        end
endtask

// Back-to-back reads on an idle bus (upstream e21a9ce)
task automatic consecutive_reads();
    axi_addr_t a = MemBase + 32'h200;
    for (int unsigned i = 0; i < 8; i++) do_write(0, a + i * 4, 1, 3'd2, 1'b0);
    for (int unsigned pass = 0; pass < 2; pass++)
        for (int unsigned i = 0; i < 8; i++) do_read(0, "consecutive", a + i * 4, 1, 3'd2);
endtask

// CR0 through register space; with two PHYs each carries one halfword
task automatic program_cr0(int unsigned latency, bit fixed);
    logic [15:0] cr0;
    logic [3:0]  code;
    case (latency)
        3: code = 4'b1110;
        4: code = 4'b1111;
        5: code = 4'b0000;
        7: code = 4'b0010;
        default: code = 4'b0001;
    endcase
    cr0 = {1'b1, 3'b000, 4'b1111, code, fixed, 1'b1, 2'b11};
    reg_write(HBT_REG_ADDRESS_SPACE, 1);
    for (int unsigned c = 0; c < NumChips; c++) begin
        axi_data_t   data [1];
        axi_strb_t   strb [1];
        axi_addr_t   a = MemBase + c * ChipSpace + (32'h800 << NumPhys);
        data[0] = '0;
        strb[0] = '0;
        for (int unsigned p = 0; p < NumPhys; p++) begin
            data[0][(8 * (a % SW)) + 16 * p +: 16] = cr0;
            strb[0][(a % SW) + 2 * p +: 2]         = 2'b11;
        end
        axi_write(0, a, 1, 3'($clog2(2 * NumPhys)), data, strb);
    end
    reg_write(HBT_REG_ADDRESS_SPACE, 0);
    reg_write(HBT_REG_T_LATENCY_ACCESS, latency);
    reg_write(HBT_REG_EN_LATENCY_ADDITIONAL, 0);    // decide from RWDS
endtask

realtime t_traffic;

initial begin
    logic [31:0] v;
    wait (clk_run);
    $write("[hbt] system %s: %0d PHY x %0d chips, AXI %0d bit, ",
           HBT_SYSTEM, NumPhys, NumChips, DW);
    $display("corner %s, tck %.3f ns, HyperBus CK %.3f ns",
             corner_name(hbt_cfg.corner), hbt_cfg.tck_ns, hbt_cfg.ck_ns);
    $write("[hbt] board load %.1f pF, flight %.2f +/- %.2f ns; ",
           hbt_cfg.load_pf, hbt_cfg.flight_ns, hbt_cfg.flight_skew_ns);
    $display("clock duty %.2f; on-chip variation %.1f %% (pattern %0d)",
             hbt_cfg.duty, 100.0 * hbt_cfg.ocv, hbt_cfg.ocv_pattern);
    $write("[hbt] device %s, tCKDS %.2f ns, tDSV %.2f ns, ",
           hbt_mem.name, hbt_cfg.mem_tckds, hbt_cfg.mem_tdsv);
    $display("DQ-RWDS skew +/- %.2f ns, RWDS mode %0d", hbt_cfg.mem_dq_skew, hbt_cfg.rwds_mode);
    $display("[hbt] on-chip delays: %s", hbt_chip.src);
    $display("[hbt] delay line: %s", HBT_DLINE_SRC);
    $display("[hbt] pads: %s", HBT_PAD_SRC);
    repeat (10) @(posedge clk);
    #1 rst_n = 1'b1;

    repeat (20) @(posedge clk);
    if (!hbt_cfg.keep_reset_taps) begin
`ifdef HBT_TX_DELAYED
        reg_write(HBT_REG_T_TX_CLK_DELAY, hbt_cfg.tx_code);
`endif
        reg_write(HBT_REG_T_RX_CLK_DELAY, hbt_cfg.rx_code);
    end
    // +t_burst_max=N bounds CS# low (tCSM)
    if ($test$plusargs("t_burst_max")) reg_write(HBT_REG_T_BURST_MAX, plus_int("t_burst_max", 140));
    reg_read(HBT_REG_T_TX_CLK_DELAY, v); hbt_cfg.tx_code = v;
    reg_read(HBT_REG_T_RX_CLK_DELAY, v); hbt_cfg.rx_code = v;
    $display("[hbt] t_tx_clk_delay %0d (%.3f/%.3f ns), t_rx_clk_delay %0d (%.3f/%.3f ns)",
             hbt_cfg.tx_code, dline(hbt_cfg.corner, hbt_cfg.tx_code % HBT_NUM_CODES, 1),
             dline(hbt_cfg.corner, hbt_cfg.tx_code % HBT_NUM_CODES, 0),
             hbt_cfg.rx_code, dline(hbt_cfg.corner, hbt_cfg.rx_code % HBT_NUM_CODES, 1),
             dline(hbt_cfg.corner, hbt_cfg.rx_code % HBT_NUM_CODES, 0));

    // Wait out Startup so the watchdog only times real transfers
    wait (`HBT_PHY(0).state_q != hyperbus_pkg::Startup);
    $display("[hbt] PHY out of startup at %.1f us", $realtime / 1000.0);

    if (hbt_cfg.program_cr0) program_cr0(hbt_cfg.mem_latency, hbt_cfg.mem_fixed_latency);

    t_traffic = $realtime;
    consecutive_reads();
    long_bursts(hbt_cfg.long_bursts);
    fork
        thread_mix(hbt_cfg.n_txn);
        thread_stream(hbt_cfg.n_txn / 4);
    join
    finish_report();
end

task automatic finish_report();
    int unsigned vio = 0, mem_vio = 0, n_cont = 0;
    real ws [4], wh [4];
    real max_dq = 0.0, max_rwds = 0.0;
    int unsigned n_dq = 0, n_rwds = 0;
    hbt_dev_result_t worst_dev;
    bit  pass;

    hbt_report_req++;
    #0.001;
    foreach (ws[g]) begin ws[g] = 1.0e9; wh[g] = 1.0e9; end
    worst_dev.worst_tcss = 1.0e9; worst_dev.worst_tcsh = 1.0e9; worst_dev.worst_tcshi = 1.0e9;
    worst_dev.worst_trwr = 1.0e9; worst_dev.worst_tckhp = 1.0e9; worst_dev.max_cs_low = 0.0;

    $display("");
    $display("=================================================================================");
    $display(" HyperBus timing: %s, corner %s, TX code %0d, RX code %0d, %s", HBT_SYSTEM,
             corner_name(hbt_cfg.corner), hbt_cfg.tx_code, hbt_cfg.rx_code, hbt_mem.name);
    $display("=================================================================================");
    $display(" %-32s %s %s %s %s %s",
             "check", rjust("samples", 8), rjust("setup ns", 9), rjust("hold ns", 9),
             rjust("#su", 6), rjust("#ho", 6));
    foreach (hbt_chk_results[i]) begin
        hbt_chk_result_t r = hbt_chk_results[i];
        string su_s, ho_s;
        su_s = (r.n_checked == 0) ? "-" : $sformatf("%.3f", r.worst_setup);
        ho_s = (r.n_checked == 0) ? "-"
                                  : $sformatf("%.3f", r.worst_hold > 1.0e8 ? 99.999 : r.worst_hold);
        $display(" %-32s %s %s %s %s %s",
                 r.name, rjust($sformatf("%0d", r.n_checked), 8), rjust(su_s, 9), rjust(ho_s, 9),
                 rjust($sformatf("%0d", r.n_setup_vio), 6),
                 rjust($sformatf("%0d", r.n_hold_vio), 6));
        vio += r.n_setup_vio + r.n_hold_vio;
        if (r.n_checked == 0) continue;
        if (r.worst_setup < ws[r.grp]) ws[r.grp] = r.worst_setup;
        if (r.worst_hold  < wh[r.grp]) wh[r.grp] = r.worst_hold;
    end
    foreach (hbt_dev_results[i]) begin
        hbt_dev_result_t d = hbt_dev_results[i];
        mem_vio += d.n_vio;
        if (d.worst_tcss  < worst_dev.worst_tcss)  worst_dev.worst_tcss  = d.worst_tcss;
        if (d.worst_tcsh  < worst_dev.worst_tcsh)  worst_dev.worst_tcsh  = d.worst_tcsh;
        if (d.worst_tcshi < worst_dev.worst_tcshi) worst_dev.worst_tcshi = d.worst_tcshi;
        if (d.worst_trwr  < worst_dev.worst_trwr)  worst_dev.worst_trwr  = d.worst_trwr;
        if (d.worst_tckhp < worst_dev.worst_tckhp) worst_dev.worst_tckhp = d.worst_tckhp;
        if (d.max_cs_low  > worst_dev.max_cs_low)  worst_dev.max_cs_low  = d.max_cs_low;
    end
    foreach (hbt_bus_results[i]) begin
        n_dq   += hbt_bus_results[i].n_dq;
        n_rwds += hbt_bus_results[i].n_rwds;
        if (hbt_bus_results[i].max_dq   > max_dq)   max_dq   = hbt_bus_results[i].max_dq;
        if (hbt_bus_results[i].max_rwds > max_rwds) max_rwds = hbt_bus_results[i].max_rwds;
    end
    n_cont = n_dq + n_rwds;
    $write(" device protocol: tCSS min %.3f, tCSH min %.3f, tCSHI min %.3f, tRWR min %.3f, ",
           worst_dev.worst_tcss, worst_dev.worst_tcsh, worst_dev.worst_tcshi, worst_dev.worst_trwr);
    $display("CK half-period min %.1f %%, CS# low max %.1f ns",
             100.0 * worst_dev.worst_tckhp, worst_dev.max_cs_low);
    $display(" device violations %0d, bus contention DQ %0d (max %.3f ns) RWDS %0d (max %.3f ns)",
             mem_vio, n_dq, max_dq, n_rwds, max_rwds);
    $write(" traffic: %0d reads, %0d writes, %0d bytes checked, ",
           n_reads, n_writes, n_bytes_checked);
    $display("%0d mismatches, %0d AXI errors, %0d hangs", n_mismatch, n_axi_err, n_hang);
    pass = (vio == 0) && (mem_vio == 0) && (n_mismatch == 0) && (n_axi_err == 0) && (n_hang == 0) &&
           (n_cont == 0) && (hbt_chk_results.size() > 0);
    $display(" RESULT: %s", pass ? "PASS" : "FAIL");
    $display("=================================================================================");
    // One line, parsed by hbtlib/sweep.py
    $write("HBT_RESULT corner=%s tx=%0d rx=%0d mem=%s tckds=%.2f rwds_mode=%0d status=%s",
           corner_name(hbt_cfg.corner), hbt_cfg.tx_code, hbt_cfg.rx_code, hbt_mem.name,
           hbt_cfg.mem_tckds, hbt_cfg.rwds_mode, pass ? "PASS" : "FAIL");
    $write(" timing_vio=%0d mem_vio=%0d mism=%0d hang=%0d cont=%0d",
           vio, mem_vio, n_mismatch, n_hang, n_cont);
    $write(" mem_su=%.3f mem_ho=%.3f rx_su=%.3f rx_ho=%.3f",
           ws[GrpMem], wh[GrpMem], ws[GrpRx], wh[GrpRx]);
    $write(" rws_su=%.3f rws_ho=%.3f int_su=%.3f int_ho=%.3f",
           ws[GrpRws], wh[GrpRws], ws[GrpInt], wh[GrpInt]);
    $display(" reads=%0d writes=%0d cs_low_max=%.1f", n_reads, n_writes, worst_dev.max_cs_low);
    $finish;
endtask

endmodule
