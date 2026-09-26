// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Matej Jurasić <matej.jurasic@cappig.dev>

// Delay-line model replacing configurable_delay: wire in + tap delay (per code,
// edge and corner) + wire out. The role comes from the instance path: the RX
// RWDS line adds the pad route and the capture clock tree, the TX line adds
// the clock-root latency (CK/CS# wiring is added at the pads).
`include "hbt_defines.svh"

module configurable_delay #(
    parameter int unsigned NUM_STEPS = 16,
    localparam int unsigned SelW = $clog2(NUM_STEPS)
) (
    input  logic            clk_i,
`ifdef HBT_DL_ENABLE
    input  logic            enable_i,
`endif
    input  logic [SelW-1:0] delay_i,
    output logic            clk_o
);

import hbt_pkg::*;

bit      rx = 1'b0;
real     pre_ns, post_ns;
realtime last_out = 0.0;

initial begin
    automatic string path = $sformatf("%m");
    for (int i = 0; i + 18 <= path.len(); i++)
        if (path.substr(i, i + 17) == "i_delay_rx_rwds_90") rx = 1'b1;
    #0;  // hbt_chip is loaded at time 0
    pre_ns  = rx ? hbt_chip.rwds_in_dl : hbt_chip.dl_tx_in;
    post_ns = rx ? hbt_chip.rx_pos_min : 0.0;
    $display("[hbt] %s delay line (%s): in %.3f ns, out %.3f ns",
             rx ? "RX" : "TX", path, pre_ns, post_ns);
end

initial clk_o = 1'b0;

// Transport delay; a code change mid-flight cannot reorder edges
always @(clk_i) begin
    automatic logic    v = clk_i;
    automatic realtime t = $realtime + pre_ns + dline(hbt_cfg.corner, int'(delay_i), v) + post_ns;
    if (t <= last_out) t = last_out + 0.001;
    last_out = t;
    fork
        #(t - $realtime) clk_o = v;
    join_none
end

endmodule
