// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Matej Jurasic <matej.jurasic@cappig.dev>

#pragma once

#include <cstdint>

// name, width
#define TB_INPUTS(X)                                                            \
    X(clk_i, 1) X(rst_ni, 1)                                                    \
    X(jtag_tck_i, 1) X(jtag_tms_i, 1) X(jtag_tdi_i, 1) X(jtag_trst_ni, 1)       \
    X(uart0_rx_i, 1) X(boot_sel_i, 2)                                           \
    X(gpio_a_i, 8) X(gpio_a_tb_oe_i, 8)                                         \
    X(qspi0_sd_i, 4) X(qspi0_sd_tb_oe_i, 4)                                     \
    X(hyper_dq_i, 8) X(hyper_dq_tb_oe_i, 1)                                     \
    X(hyper_rwds_i, 1) X(hyper_rwds_tb_oe_i, 1)                                 \
    X(float_i, 32)

#define TB_OUTPUTS(X)                                                           \
    X(end_o, 1) X(result_o, 32)                                                 \
    X(jtag_tdo_o, 1) X(uart0_tx_o, 1) X(heartbeat_o, 1)                         \
    X(gpio_a_o, 8) X(gpio_a_oe_o, 8)                                            \
    X(qspi0_sck_o, 1) X(qspi0_cs_o, 3) X(qspi0_sd_o, 4) X(qspi0_sd_oe_o, 4)     \
    X(hyper_dq_o, 8) X(hyper_dq_oe_o, 1) X(hyper_rwds_o, 1)                     \
    X(hyper_rwds_oe_o, 1) X(hyper_ck_o, 1) X(hyper_cs_no, 2)                    \
    X(hyper_reset_no, 1) X(contention_o, 32)

class IcarusContext {
  public:
    void time(uint64_t ps) { time_ = ps; }
    uint64_t time() const { return time_; }

  private:
    uint64_t time_ = 0;
};

class Vtb_chip {
  public:
#define TB_FIELD(name, width) uint32_t name = 0;
    TB_INPUTS(TB_FIELD)
    TB_OUTPUTS(TB_FIELD)
#undef TB_FIELD

    void eval();
    void final() {}

    // vvp runs to the horizon or until a watched pad changes
    bool eventsPending();
    uint64_t nextTimeSlot() const;
    void set_horizon(uint64_t time);

    IcarusContext* contextp() { return &context_; }

  private:
    IcarusContext context_;
};
