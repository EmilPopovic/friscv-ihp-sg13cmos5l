#pragma once

#include <cstdint>

#include "Vfriscv_chip_soc.h"

using Dut = Vfriscv_chip_soc;

namespace dut {

constexpr unsigned QSPI_SD_LSB   = 5;   // PA5..PA8 = IO0..IO3
constexpr unsigned QSPI_SCK_BIT  = 9;
constexpr unsigned QSPI_CS0_BIT  = 10;
constexpr unsigned QSPI_MISO_BIT = QSPI_SD_LSB + 1;

inline void clear_inputs(Dut& top) {
    top.pad_in_i = 0;
}

inline void set_strap(Dut& top, unsigned bit) {
    top.pad_in_i |= uint32_t(1) << bit;
}

inline bool qspi_sck(const Dut& top) {
    return ((top.pad_out_o >> QSPI_SCK_BIT) & 1) != 0;
}

inline bool qspi_selected(const Dut& top) {
    return ((top.pad_out_o >> QSPI_CS0_BIT) & 1) == 0;
}

inline bool qspi_mosi(const Dut& top) {
    return ((top.pad_out_o >> QSPI_SD_LSB) & 1) != 0;
}

inline void qspi_miso(Dut& top, bool value) {
    top.pad_in_i = (top.pad_in_i & ~(uint32_t(1) << QSPI_MISO_BIT)) |
                   (uint32_t(value ? 1 : 0) << QSPI_MISO_BIT);
}

}  // namespace dut
