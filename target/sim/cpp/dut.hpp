#pragma once

#include <cstdint>

#include "Vfriscv_chip_soc.h"

using Dut = Vfriscv_chip_soc;

namespace dut {

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

inline bool qspi_selected(const Dut& top) {
    return (top.qspi0_cs_o & 1) == 0;
}

inline bool qspi_mosi(const Dut& top) {
    return ((top.qspi0_sd_o >> QSPI_MOSI_BIT) & 1) != 0;
}

inline void qspi_miso(Dut& top, bool value) {
    top.qspi0_sd_i = uint8_t((top.qspi0_sd_i & ~(uint32_t(1) << QSPI_MISO_BIT)) |
                             (uint32_t(value ? 1 : 0) << QSPI_MISO_BIT));
}

}  // namespace dut
