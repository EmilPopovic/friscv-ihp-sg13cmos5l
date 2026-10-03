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

HARNESS_DEFS = \
	-DFRISCV_SOC_SRAM_BASE=$(SOC_SRAM_BASE)             \
	-DFRISCV_SOC_SRAM_SIZE_BYTES=$(SOC_SRAM_SIZE_BYTES) \
	-DFRISCV_MEM_CHIP_BYTES=$(SOC_MEM_SIZE)             \
	-DFRISCV_CLK_PERIOD_PS=$(CLK_PERIOD_PS)

VERILATOR_CPP_FLAGS = \
	-CFLAGS -I$(CURDIR)/cpp -CFLAGS -I$(abspath $(SHARED_DIR)) \
	$(addprefix -CFLAGS ,$(HARNESS_DEFS))

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

# The harness runs in vvp as a VPI module
GLS_VVP = $(GLS_DIR)/gls.vvp
GLS_VPI = $(GLS_DIR)/vernii.vpi
GLS_SIM = vvp -n -M $(CURDIR)/$(GLS_DIR) -m vernii $(CURDIR)/$(GLS_VVP)

GLS_CPP = cpp/icarus/vpi_harness.cpp $(HARNESS_CPP)
GLS_HPP = $(wildcard cpp/icarus/*.h) $(HARNESS_HPP)

GLS_SOURCES = rtl/tb_gls.sv rtl/tb_chip_nl.sv rtl/bondpad_70x70_5L.v rtl/delay_line_sim.sv \
	$(PDK_SIM_MODELS) $(NETLIST)

$(GLS_VPI): $(GLS_CPP) $(GLS_HPP) $(SHARED_CPP) $(SHARED_HPP) | $(GLS_DIR)
	$(CXX) -std=c++17 -O2 -fPIC $(filter -I%,$(shell iverilog-vpi --cflags))  \
		-Icpp/icarus -Icpp -I$(SHARED_DIR) -DFRISCV_DUT_CHIP -DFRISCV_DUT_ICARUS \
		$(HARNESS_DEFS) -Dmain=harness_main $(GLS_CPP) $(SHARED_CPP)          \
		$(shell iverilog-vpi --ldflags) $(shell iverilog-vpi --ldlibs) -lpthread -o $@

$(GLS_VVP): $(GLS_SOURCES) | $(GLS_DIR)
	@test -n "$(NETLIST)" || { echo "no netlist; pass NETLIST=<RVSoC9108.nl.v>" >&2; exit 1; }
	iverilog -g2012 -o $@ -s tb_gls $(GLS_SOURCES) 2>&1 \
		| grep -v 'sorry: ifnone with an edge-sensitive path' || true
	@test -f $@
	@echo "netlist: $(NETLIST)"

gls: $(GLS_VVP) $(GLS_VPI)

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

# run for the directed tests, act for the act tests
GLS_TESTS ?= run act

test-gls: gls
	$(if $(filter act,$(GLS_TESTS)),$(MAKE) -C tests act-elfs)
	$(MAKE) -C tests $(GLS_TESTS) -j$(shell nproc) SIM="$(GLS_SIM)" SEEDS=1 B=build_gls PROGRESS=600

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

.PHONY: all soc chip gls test test-soc test-gls jtag debug clean
