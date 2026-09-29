// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

#pragma once

#include <cstdint>
#include <vector>

#include "dut.hpp"
#include "hyperram.hpp"
#include "qspi_flash.hpp"
#include "sd_card.hpp"
#include "uart_rx_driver.hpp"
#include "uart_tx_monitor.hpp"

#ifndef FRISCV_MEM_CHIP_BYTES
#define FRISCV_MEM_CHIP_BYTES 0x2000000
#endif

#ifndef FRISCV_CLK_PERIOD_PS
#define FRISCV_CLK_PERIOD_PS 13330
#endif

class SocTestbench {
  public:
    static constexpr unsigned HYPER_CHIPS = 2;
    static constexpr uint32_t HYPER_CHIP_BYTES = FRISCV_MEM_CHIP_BYTES;

    SocTestbench();
    ~SocTestbench();

    Dut& top() { return top_; }
    Hyperram& ext_mem(unsigned chip) { return ext_mem_[chip]; }
    QspiFlash& flash() { return flash_; }
    SdCard& sd() { return sd_; }
    UartTxMonitor& uart() { return uart_; }
    UartRxDriver& uart_rx() { return uart_rx_; }

    // Offset from MEM_BASE
    void preload_ext(uint32_t offset, const std::vector<uint8_t>& data);

    void set_float_seed(uint32_t seed);

    void reset();
    void run_cycles(uint64_t count);
    uint64_t cycles() const { return cycles_; }

    // Pads the chip driving lines at the same time
    uint32_t contention() const { return contention_; }

  private:
    void eval();
    void advance(uint64_t time);
    void drive_miso();
    void drive_hyperbus();
    void check_contention();
    uint32_t next_float();

    Dut top_;
    Hyperram ext_mem_[HYPER_CHIPS];
    QspiFlash flash_;
    SdCard sd_;
    UartTxMonitor uart_;
    UartRxDriver uart_rx_;
    uint64_t cycles_ = 0;
    uint64_t time_ = 0;
    uint32_t float_state_ = 1;
    uint32_t contention_ = 0;
    bool models_on_ = false;
};
