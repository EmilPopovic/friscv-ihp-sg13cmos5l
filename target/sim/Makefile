# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

SOC_SRAM_BASE ?= 0
SOC_SRAM_SIZE_BYTES ?= 8192
SOC_MEM_SIZE ?= 33554432

CLK_PERIOD_PS ?= 13330

SOC_DIR  ?= obj_dir_soc
CHIP_DIR ?= obj_dir_chip
GLS_DIR  ?= obj_dir_gls

SOC_BIN  = $(SOC_DIR)/friscv_soc
CHIP_BIN = $(CHIP_DIR)/chip_sim
GLS_BIN  = $(GLS_DIR)/gls.vvp

# Which build to do (chip/soc/debug)
SIM ?= chip
SIM_BIN = $(if $(filter soc,$(SIM)),$(SOC_BIN),$(CHIP_BIN))

TARGET_DIR = $(abspath ../ihp-sg13cmos5l)
PDK_LIBS   = $(PDK_ROOT)/ihp-sg13cmos5l/libs.ref

# Netlist of the newest LibreLane run
NETLIST ?= $(firstword $(wildcard $(shell ls -td $(TARGET_DIR)/librelane/runs/*/final/nl 2>/dev/null | head -1)/RVSoC9108.nl.v))

##############
# Shared C++ #
##############

VERNII_SIM = $(shell bender -d ../.. path vernii)/target/sim
SHARED_MODELS = elf_loader jtag paged_mem qspi_flash remote_bitbang sd_card \
	uart_rx_driver uart_tx_monitor
SHARED_DIR = obj_dir_vernii
SHARED_CPP = $(addprefix $(SHARED_DIR)/,$(addsuffix .cpp,$(SHARED_MODELS)))
SHARED_HPP = $(SHARED_CPP:.cpp=.hpp)

HARNESS_CPP = cpp/hyperram.cpp cpp/soc_testbench.cpp cpp/tb_main.cpp
HARNESS_HPP = $(wildcard cpp/*.hpp)

$(SOC_DIR) $(CHIP_DIR) $(GLS_DIR) $(SHARED_DIR):
	mkdir -p $@

$(SHARED_DIR)/%: $(VERNII_SIM)/cpp/% | $(SHARED_DIR)
	cp $< $@

VERILATOR_CPP_FLAGS = \
	-CFLAGS -I$(CURDIR)/cpp -CFLAGS -I$(abspath $(SHARED_DIR))  \
	-CFLAGS -DFRISCV_SOC_SRAM_BASE=$(SOC_SRAM_BASE)             \
	-CFLAGS -DFRISCV_SOC_SRAM_SIZE_BYTES=$(SOC_SRAM_SIZE_BYTES) \
	-CFLAGS -DFRISCV_MEM_CHIP_BYTES=$(SOC_MEM_SIZE)             \
	-CFLAGS -DFRISCV_CLK_PERIOD_PS=$(CLK_PERIOD_PS)

#############
# SoC build #
#############

sources.f: ../../Bender.yml ../../Bender.lock
	bender -d ../.. script flist-plus -t rtl -t synthesis > $@
	sed -i '\|/opentitan_peripherals-[^/]*/src/spi_host/rtl/|d' $@
	sed -i '\|/obi_peripherals-[^/]*/hw/obi_uart/|d' $@

$(SOC_BIN): sources.f $(HARNESS_CPP) cpp/soc_memory.cpp $(HARNESS_HPP) \
		$(SHARED_CPP) $(SHARED_HPP) | $(SOC_DIR)
	verilator --cc --exe --build --timescale 1ns/1ps -j 0 --top-module chip_soc -Wno-fatal \
		+define+ASSERTS_OFF --x-assign unique --x-initial unique                           \
		-GOcmBase=$(SOC_SRAM_BASE) -GOcmSize=$(SOC_SRAM_SIZE_BYTES)                        \
		-GMemSize=$(SOC_MEM_SIZE)                                                          \
		-GHyperClockDelayed=0 -GHaltOnEnd=1 $(SOC_PARAMS)                                  \
		$(VERILATOR_CPP_FLAGS)                                                             \
		--Mdir $(SOC_DIR) -f sources.f $(HARNESS_CPP) cpp/soc_memory.cpp                   \
		$(abspath $(SHARED_CPP)) -o friscv_soc

soc: $(SOC_BIN)

##############
# Chip build #
##############

PDK_SIM_MODELS = \
	$(PDK_LIBS)/sg13cmos5l_io/verilog/sg13cmos5l_io.v                           \
	$(PDK_LIBS)/sg13cmos5l_stdcell/verilog/sg13cmos5l_udp.v                     \
	$(PDK_LIBS)/sg13cmos5l_stdcell/verilog/sg13cmos5l_stdcell.v                 \
	$(PDK_LIBS)/sg13cmos5l_sram/verilog/RM_IHPSG13_1P_core_behavioral_bm_bist.v \
	$(PDK_LIBS)/sg13cmos5l_sram/verilog/RM_IHPSG13_1P_1024x32_c2_bm_bist.v      \
	$(PDK_LIBS)/sg13cmos5l_sram/verilog/RM_IHPSG13_1P_512x32_c2_bm_bist.v       \
	$(PDK_LIBS)/sg13cmos5l_sram/verilog/RM_IHPSG13_1P_256x32_c2_bm_bist.v       \
	$(PDK_LIBS)/sg13cmos5l_sram/verilog/RM_IHPSG13_1P_64x64_c2_bm_bist.v

chip_sources.f: ../../Bender.yml ../../Bender.lock $(wildcard rtl/*.sv) \
		$(wildcard $(TARGET_DIR)/src/*.sv)
	@test -n "$(PDK_ROOT)" || { echo "PDK_ROOT is not set" >&2; exit 1; }
	bender -d ../.. script flist-plus -t rtl -t synthesis > $@
	sed -i '\|/tech_cells_generic-[^/]*/src/rtl/tc_sram\.sv$$|d' $@
	sed -i '\|/tech_cells_generic-[^/]*/src/rtl/tc_clk\.sv$$|d' $@
	sed -i '\|/opentitan_peripherals-[^/]*/src/spi_host/rtl/|d' $@
	sed -i '\|/obi_peripherals-[^/]*/hw/obi_uart/|d' $@
	sed -i '\|/hw/configurable_delay\.sv$$|d' $@
	echo "$(TARGET_DIR)/src/tc_sram.sv" >> $@
	echo "$(TARGET_DIR)/src/stubs/tc_clk.sv" >> $@
	echo "$(TARGET_DIR)/src/mc_delay.sv" >> $@
	echo "$(TARGET_DIR)/src/RVSoC9108.sv" >> $@
	for f in $(PDK_SIM_MODELS); do echo "$$f" >> $@; done
	echo "$(CURDIR)/rtl/delay_line_sim.sv" >> $@
	echo "$(CURDIR)/rtl/tb_chip.sv" >> $@

$(CHIP_BIN): chip_sources.f $(HARNESS_CPP) $(HARNESS_HPP) \
		$(SHARED_CPP) $(SHARED_HPP) | $(CHIP_DIR)
	verilator --cc --exe --build --timing --timescale 1ns/1ps -j 0 --top-module tb_chip \
		-Wno-fatal -Wno-lint -Wno-style                                                 \
		+define+FUNCTIONAL +define+TARGET_ASIC +define+ASSERTS_OFF                      \
		--x-assign unique --x-initial unique                                            \
		-CFLAGS -DFRISCV_DUT_CHIP $(VERILATOR_CPP_FLAGS)                                \
		--Mdir $(CHIP_DIR) -f chip_sources.f $(HARNESS_CPP)                             \
		$(abspath $(SHARED_CPP)) -o chip_sim

chip: $(CHIP_BIN)

##############
# Gate level #
##############

# Icarus 4-state sim on the final netlist
GLS_SOURCES = rtl/tb_gls.sv rtl/bondpad_70x70_5L.v rtl/delay_line_sim.sv $(PDK_SIM_MODELS)

$(GLS_BIN): $(GLS_SOURCES) $(NETLIST) | $(GLS_DIR)
	@test -n "$(NETLIST)" || { echo "no netlist; pass NETLIST=<RVSoC9108.nl.v>" >&2; exit 1; }
	iverilog -g2012 -o $@ -s tb_gls $(GLS_SOURCES) $(NETLIST) 2>&1 \
		| grep -v 'sorry: ifnone with an edge-sensitive path' || true
	@test -f $@

gls: $(GLS_BIN)
	@echo "netlist: $(NETLIST)"
	vvp -n $(GLS_BIN) $(GLS_ARGS) | tee $(GLS_DIR)/gls.log
	@grep -q '^PASS' $(GLS_DIR)/gls.log

###################
# Tests and tools #
###################

test: chip
	$(MAKE) -C tests run SIM=$(CURDIR)/$(CHIP_BIN)

# Run from external memory, through the LLC
$(B)/%.elf: $(DIRECTED)/%.S $(DIRECTED)/link.ld | $(B)
	$(CROSS)gcc $(CFLAGS) -T $(DIRECTED)/link.ld -o $@ $<


test-soc: soc
	$(MAKE) -C tests run SIM=$(CURDIR)/$(SOC_BIN)

jtag: $(SIM_BIN)
	@test -n "$(ELF)" || { echo "usage: make jtag ELF=<program.elf> [SIM=chip|soc]" >&2; exit 1; }
	$(SIM_BIN) load "$(ELF)"

debug: $(SIM_BIN)
	@set -eu;                                                                                    \
	$(SIM_BIN) server &                                                                          \
	sim_pid=$$!;                                                                                 \
	trap 'kill $$sim_pid 2>/dev/null || true; wait $$sim_pid 2>/dev/null || true' EXIT INT TERM; \
	openocd -f $(VERNII_SIM)/openocd.cfg

clean:
	rm -rf $(SOC_DIR) $(CHIP_DIR) $(GLS_DIR) $(SHARED_DIR) sources.f chip_sources.f
	$(MAKE) -C tests clean

all: soc chip

.PHONY: all soc chip gls test test-soc jtag debug clean
