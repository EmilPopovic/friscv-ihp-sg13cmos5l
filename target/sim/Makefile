SOC_SRAM_BASE ?= 0
SOC_SRAM_SIZE_BYTES ?= 8192
SOC_MEM_SIZE ?= 16777216

SOC_TOP = friscv_chip_soc
SOC_DIR ?= obj_dir_soc
SOC_BIN = $(SOC_DIR)/friscv_soc
SOC_CPP = cpp/elf_loader.cpp cpp/paged_mem.cpp cpp/hyperram.cpp cpp/jtag.cpp \
	cpp/remote_bitbang.cpp cpp/soc_memory.cpp cpp/qspi_flash.cpp \
	cpp/soc_testbench.cpp cpp/tb_soc_main.cpp cpp/uart_tx_monitor.cpp

sources.f: ../../Bender.yml ../../Bender.lock
	bender script flist-plus -t rtl -t synthesis > $@
	sed -i '\|/opentitan_peripherals-[^/]*/src/spi_host/rtl/|d' $@
	sed -i '\|/obi_peripherals-[^/]*/hw/obi_uart/|d' $@

$(SOC_DIR):
	mkdir -p $@

soc: sources.f | $(SOC_DIR)
	verilator --cc --exe --build -j 0 --top-module $(SOC_TOP) -Wno-fatal \
		+define+ASSERTS_OFF \
		-GSramBase=$(SOC_SRAM_BASE) -GSramSize=$(SOC_SRAM_SIZE_BYTES) \
		-GMemSize=$(SOC_MEM_SIZE) \
		-GHyperClockDelayed=0 $(SOC_PARAMS) \
		-CFLAGS -DFRISCV_SOC_SRAM_BASE=$(SOC_SRAM_BASE) \
		-CFLAGS -DFRISCV_SOC_SRAM_SIZE_BYTES=$(SOC_SRAM_SIZE_BYTES) \
		--Mdir $(SOC_DIR) -f sources.f $(SOC_CPP) -o friscv_soc

jtag: soc
	@test -n "$(ELF)" || { echo "usage: make jtag ELF=<program.elf>" >&2; exit 1; }
	$(SOC_BIN) load "$(ELF)"

debug: soc
	@set -eu; \
	$(SOC_BIN) server & \
	sim_pid=$$!; \
	trap 'kill $$sim_pid 2>/dev/null || true; wait $$sim_pid 2>/dev/null || true' EXIT INT TERM; \
	openocd -f openocd.cfg

clean:
	rm -rf $(SOC_DIR) sources.f

all: soc

.PHONY: all soc jtag debug clean
