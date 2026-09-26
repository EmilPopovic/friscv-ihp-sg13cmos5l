# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0.
# You may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
#
# Matej Jurasić <matej.jurasic@cappig.dev>

#   make sweep                     sweep configs/vernii.toml, report in work/vernii/sweep/
#   make sweep CONFIG=configs/example.toml
#   make run ARGS="+corner=slow +tx_code=9 +rx_code=12"
#   make tables                    char + extract, copied over configs/vernii/*.json
#   make signoff                   tables, sweep that must pass at the reset taps, check

CONFIG ?= configs/vernii.toml
SYSTEM := $(basename $(notdir $(CONFIG)))

.PHONY: detect build run sweep report check char extract all tables signoff
detect build sweep report check char extract all:
	./hbt $@ $(CONFIG)
tables:
	./hbt char $(CONFIG)
	./hbt extract $(CONFIG)
	cp work/$(SYSTEM)/char/delay_line.json work/$(SYSTEM)/char/pads.json \
	   work/$(SYSTEM)/extract/chip_delays.json configs/$(SYSTEM)/
signoff: tables
	./hbt sweep $(CONFIG) --require-reset
	./hbt check $(CONFIG)
run:
	./hbt run $(CONFIG) --fast $(ARGS)
