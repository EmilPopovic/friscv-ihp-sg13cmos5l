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

# Environment and arguments of each test
$(foreach t,$(EXT_TESTS),$(eval ENV_$(t) = VERNII_LLCSEL=0xf)$(eval ARGS_$(t) = test $(B)/$(t).elf))
$(foreach t,$(OCM_TESTS),$(eval ENV_$(t) = VERNII_LLCSEL=0)$(eval ARGS_$(t) = test $(B)/$(t).elf))

ENV_uart_boot      =
ARGS_uart_boot     = uartboot $(B)/uart_stage.bin
ENV_uart_boot_bs3  = VERNII_BOOT_SEL=3
ARGS_uart_boot_bs3 = uartboot $(B)/uart_stage.bin
ENV_sd_boot        = VERNII_SD_IMAGE=$(B)/sd_payload.img
ARGS_sd_boot       = qspiboot $(B)/sdflash.bin

TESTS = $(EXT_TESTS) $(OCM_TESTS) uart_boot uart_boot_bs3 sd_boot

# One log per test and seed, run with -j to run them in parallel
RUNS = $(foreach s,$(SEEDS),$(foreach t,$(TESTS),$(B)/$(t).$(s).log))

$(RUNS): $(B)/%.log: all
	@t=$(basename $*); seed=$(subst .,,$(suffix $*));                         \
	env VERNII_TEST_CYCLES=$(CYCLES) VERNII_FLOAT_SEED=$$seed $(ENV_$(basename $*)) \
	    $(SIM) $(ARGS_$(basename $*)) +verilator+rand+reset+2 +verilator+seed+$$seed \
	    > $@ 2>&1;                                                            \
	printf '%-14s seed %-3s %s\n' "$$t" "$$seed" "$$(tail -1 $@)"

run: $(RUNS)
	@fail=0; for log in $(RUNS); do tail -1 $$log | grep -q '^PASS' || fail=1; done; exit $$fail

clean:
	rm -rf $(B)

.PHONY: all run clean $(RUNS)
