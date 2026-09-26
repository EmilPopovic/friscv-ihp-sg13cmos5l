#include "soc_testbench.hpp"

namespace {

constexpr unsigned RESET_CYCLES = 20;

}  // namespace

SocTestbench::SocTestbench() : ext_mem_(top_), flash_(top_) {
    top_.clk_i = 0;
    top_.rst_ni = 0;
    top_.uart0_rx_i = 1;
    top_.jtag_tck_i = 0;
    top_.jtag_tms_i = 1;
    top_.jtag_tdi_i = 0;
    top_.jtag_trst_ni = 1;
    dut::clear_inputs(top_);

    eval();
}

SocTestbench::~SocTestbench() {
    top_.final();
}

void SocTestbench::eval() {
    top_.eval();
    ext_mem_.update();
    flash_.update();
    top_.eval();
}

void SocTestbench::reset() {
    top_.rst_ni = 0;
    run_cycles(RESET_CYCLES);

    top_.rst_ni = 1;
    run_cycles(RESET_CYCLES);
}

void SocTestbench::run_cycles(uint64_t count) {
    cycles_ += count;

    for (uint64_t i = 0; i < count; ++i) {
        uart_.sample(top_.uart0_tx_o);

        // The loop leaves the clock low, so a leading low phase would only
        // re-evaluate an unchanged model
        top_.clk_i = 1;
        eval();

        top_.clk_i = 0;
        eval();
    }
}
