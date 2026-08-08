#pragma once

#include <cstdint>

#include "dut.hpp"
#include "hyperram.hpp"
#include "qspi_flash.hpp"
#include "uart_tx_monitor.hpp"

class SocTestbench {
  public:
    SocTestbench();
    ~SocTestbench();

    Dut& top() { return top_; }
    Hyperram& ext_mem() { return ext_mem_; }
    QspiFlash& flash() { return flash_; }
    UartTxMonitor& uart() { return uart_; }

    void reset();
    void run_cycles(uint64_t count);
    uint64_t cycles() const { return cycles_; }

  private:
    void eval();

    Dut top_;
    Hyperram ext_mem_;
    QspiFlash flash_;
    UartTxMonitor uart_;
    uint64_t cycles_ = 0;
};
