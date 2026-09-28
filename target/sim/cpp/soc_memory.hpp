// Copyright 2026 FER, HPC Architecture and Application Research Center
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

#ifndef SOC_MEMORY_HPP
#define SOC_MEMORY_HPP

#include <cstdint>

#include "dut.hpp"
struct ElfImage;

void preload_sram(Dut& top, const ElfImage& image,
                  uint32_t sram_base);

#endif
