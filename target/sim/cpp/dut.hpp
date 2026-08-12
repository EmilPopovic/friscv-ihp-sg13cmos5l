#pragma once

#include <cstdint>

#include "Vfriscv_chip_soc.h"

using Dut = Vfriscv_chip_soc;

namespace dut {

constexpr unsigned QSPI_MOSI_BIT = 0;  // QSPI0_IO0
constexpr unsigned QSPI_MISO_BIT = 1;  // QSPI0_IO1

inline void clear_inputs(Dut& top) {
    top.i_gpio       = 0;
    top.i_qspi_sd    = 0;
    top.i_hyper_dq   = 0;
    top.i_hyper_rwds = 0;
}

// PAn, sampled into SCB.STRAPA on the first cycles out of reset
inline void set_strap(Dut& top, unsigned bit) {
    top.i_gpio |= uint32_t(1) << bit;
}

inline bool qspi_sck(const Dut& top) {
    return top.o_qspi_sck != 0;
}

inline bool qspi_selected(const Dut& top) {
    return (top.o_qspi_csn & 1) == 0;
}

inline bool qspi_mosi(const Dut& top) {
    return ((top.o_qspi_sd >> QSPI_MOSI_BIT) & 1) != 0;
}

inline void qspi_miso(Dut& top, bool value) {
    top.i_qspi_sd = uint8_t((top.i_qspi_sd & ~(uint32_t(1) << QSPI_MISO_BIT)) |
                            (uint32_t(value ? 1 : 0) << QSPI_MISO_BIT));
}

}  // namespace dut
