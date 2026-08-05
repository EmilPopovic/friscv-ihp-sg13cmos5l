REPO_ROOT := $(abspath ../../..)
BUILD     ?= build
PART      ?= xc7z020clg400-1
TOP       ?= friscv_soc_pynq
VIVADO    ?= vivado

# act = riscv-arch-test map, chip = tapeout map, preload = act with PROG baked in
CONFIG    ?= act
PROG      ?=
LDS       ?= sw/link.ld

RV_CC     ?= riscv64-unknown-elf-gcc
RV_CFLAGS ?= -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -Wl,--no-warn-rwx-segments

SRAM_BASE := 0x80000000
SRAM_SIZE := 0x80000

SW_DIR    := build_sw
SW_ELF     = $(SW_DIR)/$(notdir $(basename $(PROG))).elf
SW_MEM     = $(SW_DIR)/$(notdir $(basename $(PROG))).mem
BIT       := $(BUILD)/$(TOP).bit
FLIST     := sources.f

ZSBL      := 1
SRAM_INIT :=

ifeq ($(CONFIG),act)
SRAM_CFG := 1
else ifeq ($(CONFIG),chip)
SRAM_CFG := 0
else ifeq ($(CONFIG),preload)
ifeq ($(PROG),)
$(error CONFIG=preload needs PROG=<program.S>; see 'make bootloader')
endif
SRAM_CFG  := 1
ZSBL      := 0
SRAM_INIT := $(CURDIR)/$(SW_MEM)
else
$(error CONFIG must be 'act', 'chip' or 'preload', got '$(CONFIG)')
endif

VIV_ENV = OUTDIR=$(CURDIR)/$(BUILD) FLIST=$(CURDIR)/$(FLIST) PART=$(PART) TOP=$(TOP) \
	  SRAM_CFG=$(SRAM_CFG) ZSBL=$(ZSBL) SRAM_INIT=$(SRAM_INIT)

.PHONY: all
all: bitstream

$(FLIST): $(REPO_ROOT)/Bender.yml $(REPO_ROOT)/Bender.lock $(wildcard src/*.sv)
	bender script flist-plus -t rtl -t synthesis -t fpga -t xilinx > $@
	sed -i '\|/opentitan_peripherals-[^/]*/src/spi_host/rtl/|d' $@
	sed -i '\|/obi_peripherals-[^/]*/hw/obi_uart/|d' $@
	sed -i '\|/tech_cells_generic-[^/]*/src/fpga/tc_sram_xilinx\.sv$$|d' $@
	echo "$(CURDIR)/src/tc_sram.sv" >> $@
	echo "$(CURDIR)/src/friscv_soc_pynq.sv" >> $@

$(BUILD) $(SW_DIR):
	mkdir -p $@

$(SW_ELF): $(PROG) $(LDS) | $(SW_DIR)
	$(RV_CC) $(RV_CFLAGS) -T $(LDS) -o $@ $(PROG)

$(SW_MEM): $(SW_ELF)
	python3 scripts/elf2mem.py $< --base $(SRAM_BASE) --size $(SRAM_SIZE) -o $@

.PHONY: sw
sw: $(SW_MEM)

DEPS := $(FLIST) $(wildcard src/*.sv) constraints/$(TOP).xdc
ifeq ($(CONFIG),preload)
DEPS += $(SW_MEM)
endif

.PHONY: synth impl bitstream
synth impl bitstream: $(DEPS) | $(BUILD)
	$(VIV_ENV) STAGE=$@ $(VIVADO) -mode batch -notrace -nojournal \
		-log $(BUILD)/vivado_$@.log -source vivado/build.tcl

# Bake in the serial bootloader, then load programs with scripts/load.sh
.PHONY: bootloader
bootloader:
	$(MAKE) bitstream CONFIG=preload PROG=sw/uart_boot.S LDS=sw/uart_boot.ld

.PHONY: program
program:
	@test -f $(BIT) || { echo "no bitstream, run 'make bitstream'" >&2; exit 1; }
	BIT=$(CURDIR)/$(BIT) $(VIVADO) -mode batch -notrace -nojournal \
		-log $(BUILD)/vivado_program.log -source scripts/program.tcl

.PHONY: report
report:
	@cat $(BUILD)/reports/summary.txt
	@grep -E '^\| +(Slice LUTs|Slice Registers|Block RAM Tile|DSPs|Bonded IOB) ' \
		$(BUILD)/reports/util.rpt

.PHONY: clean
clean:
	rm -rf $(BUILD) $(SW_DIR) $(FLIST) .Xil clockInfo.txt tight_setup_hold_pins.txt
