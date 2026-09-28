// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

#pragma once

#include <cstdint>

#include "Vchip_soc.h"

using Dut = Vchip_soc;

namespace dut {

constexpr bool PAD_RING = false;

constexpr unsigned QSPI_MOSI_BIT = 0;  // QSPI0_IO0
constexpr unsigned QSPI_MISO_BIT = 1;  // QSPI0_IO1

inline void clear_inputs(Dut& top) {
    top.boot_sel_i   = 0;
    top.gpio_a_i     = 0;
    top.qspi0_sd_i   = 0;
    top.hyper_dq_i   = 0;
    top.hyper_rwds_i = 0;
}

// Boot mode straps: 0 debug, 1 QSPI flash, 2 UART
inline void set_boot_sel(Dut& top, unsigned value) {
    top.boot_sel_i = uint8_t(value);
}

inline bool jtag_tdo(const Dut& top) {
    return top.jtag_tdo_oe_o != 0 && top.jtag_tdo_o != 0;
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

// Idles high while no device drives it
inline void qspi_miso(Dut& top, bool driven, bool value) {
    bool level = driven ? value : true;

    top.qspi0_sd_i = uint8_t((top.qspi0_sd_i & ~(1u << QSPI_MISO_BIT)) |
                             (uint32_t(level) << QSPI_MISO_BIT));
}

inline void hyperbus_in(Dut& top, bool dq_en, uint8_t dq, bool rwds_en, bool rwds) {
    top.hyper_dq_i   = dq_en ? dq : 0;
    top.hyper_rwds_i = rwds_en && rwds;
}

// Pin 2k is wired to pin 2k+1
inline void gpio_loopback(Dut& top) {
    uint32_t oe  = top.gpio_a_oe_o;
    uint32_t out = top.gpio_a_o;
    uint32_t neighbor_oe  = ((oe & 0x55) << 1) | ((oe >> 1) & 0x55);
    uint32_t neighbor_out = ((out & 0x55) << 1) | ((out >> 1) & 0x55);

    top.gpio_a_i = uint8_t((oe & out) | (~oe & neighbor_oe & neighbor_out));
}

inline void float_pads(Dut&, uint32_t) {}

inline uint32_t contention(const Dut&) {
    return 0;
}

constexpr bool HAS_RESULT = false;

inline uint32_t result(const Dut&) {
    return 0;
}

}  // namespace dut
