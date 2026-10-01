TOP = RVSoC9108

LIBRELANE = librelane librelane/config.yaml \
	--pdk ${PDK} --pdk-root ${PDK_ROOT} --manual-pdk

AREA_RUN_TAG = area
AREA_RUN_DIR = librelane/runs/$(AREA_RUN_TAG)

SRAM_LIB_DIR = ${PDK_ROOT}/ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram/lib
AREA_LIBERTIES = \
	${LIBERTY} \
	${PDK_ROOT}/ihp-sg13cmos5l/libs.ref/sg13cmos5l_io/lib/sg13cmos5l_io_typ_1p2V_3p3V_25C.lib \
	$(SRAM_LIB_DIR)/RM_IHPSG13_1P_512x32_c2_bm_bist_typ_1p20V_25C.lib \
	$(SRAM_LIB_DIR)/RM_IHPSG13_1P_64x64_c2_bm_bist_typ_1p20V_25C.lib \
	src/mc_delay/views/delay_line_D4_O1_6P000.lib

sources.f: ../../Bender.yml ../../Bender.lock $(wildcard src/*.sv)
	bender script flist-plus -t rtl -t synthesis > $@
	sed -i '\|/tech_cells_generic-[^/]*/src/rtl/tc_sram\.sv$$|d' $@
	sed -i '\|/tech_cells_generic-[^/]*/src/rtl/tc_clk\.sv$$|d' $@
	sed -i '\|/opentitan_peripherals-[^/]*/src/spi_host/rtl/|d' $@
	sed -i '\|/obi_peripherals-[^/]*/hw/obi_uart/|d' $@
	sed -i '\|/hw/configurable_delay\.sv$$|d' $@
	echo "$(CURDIR)/src/stubs/RM_IHPSG13_1P_1024x32_c2_bm_bist.sv" >> $@
	echo "$(CURDIR)/src/stubs/RM_IHPSG13_1P_512x32_c2_bm_bist.sv" >> $@
	echo "$(CURDIR)/src/stubs/RM_IHPSG13_1P_256x32_c2_bm_bist.sv" >> $@
	echo "$(CURDIR)/src/stubs/RM_IHPSG13_1P_64x64_c2_bm_bist.sv" >> $@
	echo "$(CURDIR)/src/stubs/delay_line_D4_O1_6P000.sv" >> $@
	echo "$(CURDIR)/src/stubs/sg13cmos5l_stdcell_stubs.sv" >> $@
	echo "$(CURDIR)/src/stubs/sg13cmos5l_io_stubs.v" >> $@
	echo "$(CURDIR)/src/tc_sram.sv" >> $@
	echo "$(CURDIR)/src/stubs/tc_clk.sv" >> $@
	echo "$(CURDIR)/src/mc_delay.sv" >> $@

.PHONY: area
area: sources.f
	rm -f area.rpt
	$(LIBRELANE) --run-tag $(AREA_RUN_TAG) --overwrite --to Yosys.Synthesis
	netlist=$$(echo $(AREA_RUN_DIR)/*-yosys-synthesis/$(TOP).nl.v); \
	yosys -p "read_verilog -sv $$netlist; stat $(foreach lib,$(AREA_LIBERTIES),-liberty $(lib))" | tee area.rpt

IO_CDL = build/sg13cmos5l_io.cdl

# Apply IO CDL patch to fix LVS
$(IO_CDL): ${PDK_ROOT}/${PDK}/libs.ref/sg13cmos5l_io/cdl/sg13cmos5l_io.cdl patches/sg13cmos5l_io.cdl.patch
	mkdir -p $(@D)
	cp $< $@
	chmod u+w $@
	patch -s $@ patches/sg13cmos5l_io.cdl.patch

.PHONY: librelane
librelane: sources.f $(IO_CDL)
	$(LIBRELANE)
	$(MAKE) release

RUN ?= $(lastword $(sort $(wildcard librelane/runs/RUN_*)))
RUN_DIR = $(if $(wildcard $(RUN)/resolved.json),$(RUN),librelane/runs/$(RUN))
RELEASE_DIR = release

.PHONY: release
release: $(IO_CDL)
	rm -f $(RELEASE_DIR)/$(TOP).gds $(RELEASE_DIR)/$(TOP).gds.gz $(RELEASE_DIR)/$(TOP).cdl $(RELEASE_DIR)/run.txt
	@test -f $(RUN_DIR)/final/cdl/$(TOP).cdl || \
		{ echo "$(RUN_DIR) has no final/cdl, resume it with -F OpenROAD.WriteCDL"; exit 1; }
	mkdir -p $(RELEASE_DIR)
	cp $(RUN_DIR)/final/gds/$(TOP).gds $(RELEASE_DIR)/
	gzip -9 -n -k $(RELEASE_DIR)/$(TOP).gds
	awk 'toupper($$1) == ".SUBCKT" { skip = ($$2 in seen); seen[$$2] = 1 } !skip; toupper($$1) == ".ENDS" { skip = 0 }' \
		$(RUN_DIR)/final/cdl/$(TOP).cdl \
		$$(jq -r '.CELL_CDLS[], .PAD_CDLS[], .EXTRA_CDLS[]' $(RUN_DIR)/resolved.json) \
		> $(RELEASE_DIR)/$(TOP).cdl
	echo $(abspath $(RUN_DIR)) > $(RELEASE_DIR)/run.txt

.PHONY: check-last
check-last:
	python3 scripts/check_slew.py $(RUN_DIR)

.PHONY: librelane-openroad
librelane-openroad:
	$(LIBRELANE) --last-run --flow OpenInOpenRoad

.PHONY: librelane-klayout
librelane-klayout:
	$(LIBRELANE) --last-run --flow OpenInKLayout

.PHONY: clean
clean:
	rm -f sources.f area.rpt
	rm -rf $(AREA_RUN_DIR)
