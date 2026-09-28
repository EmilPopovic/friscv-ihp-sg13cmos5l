// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

#pragma once

#include <cstdint>
#include <vector>

#include "paged_mem.hpp"

#include "dut.hpp"

// VERNII_HRAM_<FIELD> overrides each field, so sweeps need no rebuild
struct HyperramTiming {
    unsigned latency = 6;
    bool     fixed = false;
    unsigned refresh_every = 0;
    unsigned t_csm = 0;
    bool     strict = true;

    static HyperramTiming from_env();

    // Edges from the last command byte to the controller's turnaround
    unsigned latency_edges(bool additional) const {
        return 2 * (latency << (additional ? 1 : 0)) - 3;
    }
};

// One device on one chip select. Instead of driving pins, it reports what it would drive.
class Hyperram {
  public:
    Hyperram(Dut& top, unsigned cs, uint32_t size);

    void update();
    void preload(uint32_t address, const std::vector<uint8_t>& data);

    bool driving_dq() const { return dq_en_; }
    uint8_t dq() const { return dq_; }
    bool driving_rwds() const { return rwds_en_; }
    bool rwds() const { return rwds_; }

  private:
    enum class Phase {
        Idle,
        Command,
        Wait,
        Read,
        Write,
    };

    static constexpr unsigned COMMAND_BYTES = 6;
    static constexpr unsigned TURNAROUND_EDGES = 2;

    void begin_transaction();
    void end_transaction();
    void sample_command();
    void finish_command();
    void check_turnaround();
    void violation(const char* what, unsigned expected, unsigned actual);
    void drive_read_data(bool rising_edge);
    void sample_write_data(bool rising_edge);

    Dut& top_;
    unsigned cs_;
    PagedMem memory_;
    HyperramTiming timing_;
    Phase phase_ = Phase::Idle;
    uint64_t command_ = 0;
    uint32_t address_ = 0;
    unsigned command_bytes_ = 0;
    unsigned turnaround_edges_ = 0;
    unsigned wait_edges_ = 0;
    unsigned cs_edges_ = 0;
    uint64_t transactions_ = 0;
    bool additional_latency_ = false;
    bool read_ = false;
    bool clock_ = false;
    bool dq_en_ = false;
    uint8_t dq_ = 0;
    bool rwds_en_ = false;
    bool rwds_ = false;
};
