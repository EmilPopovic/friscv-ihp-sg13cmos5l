// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

#pragma once

#include <cstdint>

#include "Vtb_chip.h"

using Dut = Vtb_chip;

namespace dut {

constexpr bool PAD_RING = true;

constexpr unsigned QSPI_MOSI_BIT = 0;  // QSPI0_IO0
constexpr unsigned QSPI_MISO_BIT = 1;  // QSPI0_IO1

inline void clear_inputs(Dut& top) {
    top.boot_sel_i         = 0;
    top.gpio_a_i           = 0;
    top.gpio_a_tb_oe_i     = 0;
    top.qspi0_sd_i         = 0;
    top.qspi0_sd_tb_oe_i   = 0;
    top.hyper_dq_i         = 0;
    top.hyper_dq_tb_oe_i   = 0;
    top.hyper_rwds_i       = 0;
    top.hyper_rwds_tb_oe_i = 0;
    top.float_i            = 0;
}

inline void set_boot_sel(Dut& top, unsigned value) {
    top.boot_sel_i = uint8_t(value);
}

inline bool jtag_tdo(const Dut& top) {
    return top.jtag_tdo_o != 0;
}

inline bool qspi_sck(const Dut& top) {
    return top.qspi0_sck_o != 0;
}

inline bool qspi_selected(const Dut& top, unsigned cs) {
    return ((top.qspi0_cs_o >> cs) & 1) == 0;
}

inline bool qspi_mosi(const Dut& top) {
    return ((top.qspi0_sd_o >> QSPI_MOSI_BIT) & 1) != 0;
}

inline void qspi_miso(Dut& top, bool driven, bool value) {
    uint32_t bit = 1u << QSPI_MISO_BIT;

    top.qspi0_sd_tb_oe_i = uint8_t((top.qspi0_sd_tb_oe_i & ~bit) | (driven ? bit : 0));
    top.qspi0_sd_i       = uint8_t((top.qspi0_sd_i & ~bit) | (value ? bit : 0));
}

inline void hyperbus_in(Dut& top, bool dq_en, uint8_t dq, bool rwds_en, bool rwds) {
    top.hyper_dq_tb_oe_i   = dq_en;
    top.hyper_dq_i         = dq;
    top.hyper_rwds_tb_oe_i = rwds_en;
    top.hyper_rwds_i       = rwds;
}

// Pin 2k is connected to pin 2k+1
inline void gpio_loopback(Dut& top) {
    uint32_t oe  = top.gpio_a_oe_o;
    uint32_t pad = top.gpio_a_o;
    uint32_t neighbor_oe  = ((oe & 0x55) << 1) | ((oe >> 1) & 0x55);
    uint32_t neighbor_pad = ((pad & 0x55) << 1) | ((pad >> 1) & 0x55);

    top.gpio_a_tb_oe_i = uint8_t(neighbor_oe & ~oe);
    top.gpio_a_i       = uint8_t(neighbor_pad);
}

inline void float_pads(Dut& top, uint32_t random) {
    top.float_i = random;
}

// Pads both sides drive
inline uint32_t contention(const Dut& top) {
    return top.contention_o;
}

constexpr bool HAS_RESULT = true;

inline uint32_t result(const Dut& top) {
    return top.result_o;
}

}  // namespace dut
