// Zero-delay stub for the hyperbus tech-dependent delay line.
module configurable_delay #(
    parameter int unsigned NUM_STEPS = 16,
    localparam int unsigned DELAY_SEL_WIDTH = $clog2(NUM_STEPS)
) (
    input  logic                       clk_i,
    input  logic                       enable_i,
    input  logic [DELAY_SEL_WIDTH-1:0] delay_i,
    output logic                       clk_o
);

    assign clk_o = clk_i;

endmodule
