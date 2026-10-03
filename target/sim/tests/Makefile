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

# Act tests with Vernii's config, at the riscv-arch-test commit Vernii pins
ACT_MAKEFILE = $(VERNII_DIR)/verif/riscv-arch-test/Makefile
ACT_CONFIG   = $(VERNII_DIR)/verif/riscv-arch-test/config/cores/friscv/friscv-soc
ACT_REPO     = $(shell sed -n 's/^ACT_REPO *:= *//p' $(ACT_MAKEFILE))
ACT_REF      = $(shell sed -n 's/^ACT_REF *:= *//p' $(ACT_MAKEFILE))
ACT_EXCLUDE  = $(shell sed -n 's/^ACT_EXCLUDE_EXTENSIONS *?= *//p' $(ACT_MAKEFILE))
ACT_ROOT     = $(CURDIR)/act/riscv-arch-test

ACT_ELFS  = $(sort $(shell find $(ACT_ROOT)/work/friscv-soc/elfs -name '*.elf' 2>/dev/null))
ACT_TESTS = $(basename $(notdir $(ACT_ELFS)))

define act_test
ENV_$(basename $(notdir $(1)))  = VERNII_LLCSEL=0xf
ARGS_$(basename $(notdir $(1))) = test $(1)
endef
$(foreach e,$(ACT_ELFS),$(eval $(call act_test,$(e))))

$(ACT_ROOT)/.git:
	git init -q $(ACT_ROOT)
	git -C $(ACT_ROOT) remote add origin $(ACT_REPO)
	git -C $(ACT_ROOT) fetch -q --depth 1 origin $(ACT_REF)
	git -C $(ACT_ROOT) checkout -q --detach FETCH_HEAD

act-elfs: $(ACT_ROOT)/.git
	rm -rf $(ACT_ROOT)/config/cores/friscv/friscv-soc $(ACT_ROOT)/work/friscv-soc
	mkdir -p $(ACT_ROOT)/config/cores/friscv/friscv-soc
	cp $(ACT_CONFIG)/* $(ACT_ROOT)/config/cores/friscv/friscv-soc/
	mise trust -q $(ACT_ROOT)/.mise.toml
	UV_LINK_MODE=copy CONFIG_FILES=config/cores/friscv/friscv-soc/test_config.yaml \
		EXCLUDE_EXTENSIONS=$(ACT_EXCLUDE) $(MAKE) -C $(ACT_ROOT) --jobs $(shell nproc)

# One log per test and seed, run with -j to run them in parallel. With PROGRESS=<seconds>,
# print how far each test is that often.
RUNS     = $(foreach s,$(SEEDS),$(foreach t,$(TESTS),$(B)/$(t).$(s).log))
ACT_RUNS = $(foreach s,$(SEEDS),$(foreach t,$(ACT_TESTS),$(B)/$(t).$(s).log))
PROGRESS ?=

verdict = { grep -E '^(PASS|FAIL)' $(1) || tail -1 $(1); } | tail -1
check   = fail=0; for log in $(1); do $(call verdict,$$log) | grep -q '^PASS' || fail=1; done; \
          exit $$fail

$(RUNS) $(ACT_RUNS): $(B)/%.log: all
	@t=$(basename $*); seed=$(subst .,,$(suffix $*));                                  \
	printf '%-14s running\n' "$$t";                                                    \
	env VERNII_TEST_CYCLES=$(CYCLES) VERNII_FLOAT_SEED=$$seed VERNII_PROGRESS=$(PROGRESS) \
	    $(ENV_$(basename $*)) $(SIM) $(ARGS_$(basename $*))                            \
	    +verilator+rand+reset+2 +verilator+seed+$$seed > $@ 2>&1 &                     \
	sim=$$!; n=0;                                                                      \
	while kill -0 $$sim 2>/dev/null; do                                                \
	    sleep 1; n=$$((n + 1));                                                        \
	    if [ -n "$(PROGRESS)" ] && [ $$((n % $(PROGRESS))) -eq 0 ]; then               \
	        p=$$(grep '^progress' $@ | tail -1 | cut -c11-);                           \
	        [ -z "$$p" ] || printf '%-14s %s\n' "$$t" "$$p";                           \
	    fi;                                                                            \
	done;                                                                              \
	printf '%-14s %s\n' "$$t" "$$($(call verdict,$@))"

run: $(RUNS)
	@$(call check,$(RUNS))

act: $(ACT_RUNS)
	@test -n "$(ACT_RUNS)" || { echo "no act tests, build them with make act-elfs" >&2; exit 1; }
	@$(call check,$(ACT_RUNS))

clean:
	rm -rf $(B)

.PHONY: all run act act-elfs clean $(RUNS) $(ACT_RUNS)
