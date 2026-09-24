// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Thomas Benz <paulsc@iis.ee.ethz.ch>
// Paul Scheffler <paulsc@iis.ee.ethz.ch>

(* no_ungroup *)
(* no_boundary_optimization *)
(* keep_hierarchy = "yes" *)
module hyperbus_delay (
    input  logic        in_i,
    input  logic [7:0]  delay_i,
    output logic        out_o
);

    // 16 taps: the delay_line_D4_O1_6P000 macro has a 4-bit select, so
    // bits 7:4 of the tap registers are ignored
    configurable_delay #(
      .NUM_STEPS(16)
    ) i_delay (
        .clk_i      ( in_i         ),
        .delay_i    ( delay_i[3:0] ),
        .clk_o      ( out_o        )
    );

endmodule : hyperbus_delay
