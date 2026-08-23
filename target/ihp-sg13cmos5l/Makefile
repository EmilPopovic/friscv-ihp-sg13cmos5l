TOP = chip_top

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

SHELL_PDK_ROOT := $(PDK_ROOT)
PDK_PATCHES    := $(sort $(wildcard pdk-patches/*.patch))
PDK_DIR        := $(CURDIR)/.pdk
PDK_STAMP      := $(PDK_DIR)/.stamp
PDK_ROOT       := $(PDK_DIR)

$(PDK_STAMP): $(PDK_PATCHES)
	@rm -rf $(PDK_DIR)
	@mkdir -p $(PDK_DIR)
	@cp -a $(SHELL_PDK_ROOT)/ihp-sg13cmos5l $(PDK_DIR)/ihp-sg13cmos5l
	@ln -sfn $(SHELL_PDK_ROOT)/ihp-sg13g2 $(PDK_DIR)/ihp-sg13g2
	@chmod -R u+w $(PDK_DIR)/ihp-sg13cmos5l
	@for p in $(PDK_PATCHES); do \
	    patch -p1 -N -s -d $(PDK_DIR)/ihp-sg13cmos5l < $$p >/dev/null 2>&1 || true; \
	    if ! patch -p1 -R -f -s --dry-run -d $(PDK_DIR)/ihp-sg13cmos5l < $$p >/dev/null 2>&1; then \
	        echo "ERROR: PDK patch $$(basename $$p) did not apply"; exit 1; \
	    fi; \
	done
	@find $(PDK_DIR)/ihp-sg13cmos5l \( -name '*.rej' -o -name '*.orig' \) -delete
	@touch $@

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
area: $(PDK_STAMP) sources.f
	rm -f area.rpt
	$(LIBRELANE) --run-tag $(AREA_RUN_TAG) --overwrite --to Yosys.Synthesis
	netlist=$$(echo $(AREA_RUN_DIR)/*-yosys-synthesis/$(TOP).nl.v); \
	yosys -p "read_verilog -sv $$netlist; stat $(foreach lib,$(AREA_LIBERTIES),-liberty $(lib))" | tee area.rpt

.PHONY: librelane
librelane: $(PDK_STAMP) sources.f
	$(LIBRELANE)

.PHONY: check-last
check-last:
	python3 signoff_report.py

.PHONY: librelane-openroad
librelane-openroad:
	$(LIBRELANE) --last-run --flow OpenInOpenRoad

.PHONY: librelane-klayout
librelane-klayout:
	$(LIBRELANE) --last-run --flow OpenInKLayout

.PHONY: clean
clean:
	rm -f sources.f area.rpt
	rm -rf $(AREA_RUN_DIR) $(PDK_DIR)
