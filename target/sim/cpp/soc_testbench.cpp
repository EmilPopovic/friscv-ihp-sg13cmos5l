// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

#include "soc_testbench.hpp"

#include <algorithm>
#include <cstdio>
#include <stdexcept>

#include "verilated.h"

namespace {

constexpr unsigned RESET_CYCLES = 20;
constexpr unsigned PRE_RESET_CYCLES = 8;

constexpr unsigned SD_PATTERN_BLOCKS = 4;

constexpr uint64_t HALF_PERIOD = FRISCV_CLK_PERIOD_PS / 2;

}  // namespace

SocTestbench::SocTestbench()
    : ext_mem_{{top_, 0, HYPER_CHIP_BYTES}, {top_, 1, HYPER_CHIP_BYTES}},
      flash_(top_),
      sd_(top_) {
    sd_.fill_test_pattern(SD_PATTERN_BLOCKS);

    // Assertions wait until reset
    Verilated::assertOn(false);

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

void SocTestbench::preload_ext(uint32_t offset, const std::vector<uint8_t>& data) {
    size_t done = 0;

    while (done < data.size()) {
        uint32_t address = offset + uint32_t(done);
        unsigned chip = address / HYPER_CHIP_BYTES;
        uint32_t within = address % HYPER_CHIP_BYTES;
        size_t size = std::min<size_t>(data.size() - done, HYPER_CHIP_BYTES - within);

        if (chip >= HYPER_CHIPS) {
            throw std::runtime_error("external preload past the last HyperRAM");
        }

        ext_mem_[chip].preload(within, std::vector<uint8_t>(data.begin() + done,
                                                            data.begin() + done + size));
        done += size;
    }
}

void SocTestbench::set_float_seed(uint32_t seed) {
    float_state_ = seed != 0 ? seed : 1;
}

// xorshift32 random floating input value
uint32_t SocTestbench::next_float() {
    float_state_ ^= float_state_ << 13;
    float_state_ ^= float_state_ >> 17;
    float_state_ ^= float_state_ << 5;
    return float_state_;
}

void SocTestbench::drive_miso() {
    // One line, two devices
    if (flash_.driving()) {
        dut::qspi_miso(top_, true, flash_.miso());
    } else if (sd_.driving()) {
        dut::qspi_miso(top_, true, sd_.miso());
    } else {
        dut::qspi_miso(top_, false, false);
    }
}

void SocTestbench::drive_hyperbus() {
    bool dq_en = false;
    bool rwds_en = false;
    uint8_t dq = 0;
    bool rwds = false;

    // One chip select is active at a time
    for (const Hyperram& chip : ext_mem_) {
        if (chip.driving_dq()) {
            dq_en = true;
            dq = chip.dq();
        }

        if (chip.driving_rwds()) {
            rwds_en = true;
            rwds = chip.rwds();
        }
    }

    dut::hyperbus_in(top_, dq_en, dq, rwds_en, rwds);
}

void SocTestbench::check_contention() {
    uint32_t pads = dut::contention(top_);

    if (pads & ~contention_) {
        std::fprintf(stderr, "pad contention 0x%08x at cycle %llu\n", pads,
                     (unsigned long long)cycles_);
    }

    contention_ |= pads;
}

void SocTestbench::eval() {
    top_.eval();

    // Only update the models after reset
    if (models_on_) {
        // Update model state
        for (Hyperram& chip : ext_mem_) {
            chip.update();
        }

        flash_.update();
        sd_.update();

        // Drive model inputs
        drive_miso();
        drive_hyperbus();
        dut::gpio_loopback(top_);

        // Update DUT
        top_.eval();

        // Check for pad contention
        check_contention();
    }
}

// Advance time to the next event for timing simulation
void SocTestbench::advance(uint64_t time) {
    while (top_.eventsPending() && top_.nextTimeSlot() < time) {
        top_.contextp()->time(top_.nextTimeSlot());
        eval();
    }

    top_.contextp()->time(time);
}

void SocTestbench::reset() {
    if (!models_on_) {
        top_.rst_ni = 1;
        run_cycles(PRE_RESET_CYCLES);
    }

    top_.rst_ni = 0;
    run_cycles(RESET_CYCLES);

    top_.rst_ni = 1;
    run_cycles(RESET_CYCLES);

    models_on_ = true;
    Verilated::assertOn(true);
}

void SocTestbench::run_cycles(uint64_t count) {
    cycles_ += count;

    for (uint64_t i = 0; i < count; ++i) {
        uart_.sample(top_.uart0_tx_o);
        top_.uart0_rx_i = uart_rx_.drive();
        dut::float_pads(top_, next_float());

        // The loop ends with the clock low
        time_ += HALF_PERIOD;
        advance(time_);
        top_.clk_i = 1;
        eval();

        time_ += HALF_PERIOD;
        advance(time_);
        top_.clk_i = 0;
        eval();
    }
}
