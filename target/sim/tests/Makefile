# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

VERNII_DIR ?= $(shell bender path vernii)
DIRECTED    = $(VERNII_DIR)/verif/directed
SDK         = $(VERNII_DIR)/sw/sdk

# Build pad ring by default
SIM   ?= $(CURDIR)/../obj_dir_chip/chip_sim
CROSS ?= riscv64-unknown-elf-
B      = build

CFLAGS := -march=rv32i_zicsr -mabi=ilp32 -nostdlib -nostartfiles -Wl,--fatal-warnings -I$(SDK)

SEEDS  ?= 1 2 3
CYCLES ?= 40000000

EXT_TESTS = llc_tags llc_counters sd_read hb_mem
OCM_TESTS = gpio_loop

ELFS = $(addprefix $(B)/,$(addsuffix .elf,$(EXT_TESTS) $(OCM_TESTS)))
BINS = $(B)/uart_stage.bin $(B)/sdflash.bin $(B)/sd_payload.img

$(B):
	mkdir -p $@

# Run from external memory
$(B)/%.elf: $(DIRECTED)/%.S $(DIRECTED)/link.ld | $(B)
	$(CROSS)gcc $(CFLAGS) -T $(DIRECTED)/link.ld -o $@ $<

$(B)/%.elf: $(DIRECTED)/%.c $(DIRECTED)/link.ld | $(B)
	$(CROSS)gcc $(CFLAGS) -O2 -Wall -Wextra -T $(DIRECTED)/link.ld -o $@ $<

$(B)/llc_counters.elf: $(DIRECTED)/llc_counters.S $(DIRECTED)/link.ld | $(B)
	sed -E 's/^(\.equ NLINE, *)8/\14/' $< > $(B)/llc_counters.S
	$(CROSS)gcc $(CFLAGS) -T $(DIRECTED)/link.ld -o $@ $(B)/llc_counters.S

$(B)/hb_mem.elf: hb_mem.S $(DIRECTED)/link.ld | $(B)
	$(CROSS)gcc $(CFLAGS) -T $(DIRECTED)/link.ld -o $@ $<

# Run from OCM
$(B)/gpio_loop.elf: gpio_loop.S | $(B)
	$(CROSS)gcc $(CFLAGS) -Wl,-Ttext=0 -o $@ $<

$(B)/uart_stage.bin: $(DIRECTED)/uart_stage.S | $(B)
	$(CROSS)gcc $(CFLAGS) -Wl,-Ttext=0 -o $(B)/uart_stage.elf $<
	$(CROSS)objcopy -O binary $(B)/uart_stage.elf $@

# The SD loader boots from flash
$(B)/sdflash.bin: $(SDK)/loaders/sdbl.c $(SDK)/loaders/loader.ld | $(B)
	$(CROSS)gcc -march=rv32ima_zicsr_zifencei -mabi=ilp32 -Os -Wall -Wextra \
		-nostdlib -nostartfiles -Wl,--no-warn-rwx-segments -I$(SDK)         \
		-T $(SDK)/loaders/loader.ld -o $(B)/sdbl.elf $<
	$(CROSS)objcopy -O binary $(B)/sdbl.elf $(B)/sdbl.bin
	python3 $(SDK)/tools/mkflash.py $(B)/sdbl.bin /dev/null $@

$(B)/sd_payload.img: $(DIRECTED)/sd_payload.S | $(B)
	$(CROSS)gcc $(CFLAGS) -Wl,-Ttext=0x80000000 -o $(B)/sd_payload.elf $<
	$(CROSS)objcopy -O binary $(B)/sd_payload.elf $(B)/sd_payload.bin
	python3 $(SDK)/tools/mksdimg.py $(B)/sd_payload.bin $@

all: $(ELFS) $(BINS)

# One line per test and seed
define run_one
	printf '%-14s seed %-3s ' "$(1)" "$(2)";                        \
	if env VERNII_TEST_CYCLES=$(CYCLES) VERNII_FLOAT_SEED=$(2) $(3) \
	   $(SIM) $(4) +verilator+rand+reset+2 +verilator+seed+$(2)     \
	   > $(B)/$(1).$(2).log 2>&1; then                              \
	    tail -1 $(B)/$(1).$(2).log;                                 \
	else                                                            \
	    tail -1 $(B)/$(1).$(2).log; fail=1;                         \
	fi;
endef

run: all
	@fail=0; \
	for seed in $(SEEDS); do \
	    $(foreach t,$(EXT_TESTS),$(call run_one,$(t),$$seed,VERNII_LLCSEL=0xf,test $(B)/$(t).elf)) \
	    $(foreach t,$(OCM_TESTS),$(call run_one,$(t),$$seed,VERNII_LLCSEL=0,test $(B)/$(t).elf)) \
	    $(call run_one,uart_boot,$$seed,,uartboot $(B)/uart_stage.bin) \
	    $(call run_one,uart_boot_bs3,$$seed,VERNII_BOOT_SEL=3,uartboot $(B)/uart_stage.bin) \
	    $(call run_one,sd_boot,$$seed,VERNII_SD_IMAGE=$(B)/sd_payload.img,qspiboot $(B)/sdflash.bin) \
	done; \
	exit $$fail

clean:
	rm -rf $(B)

.PHONY: all run clean
