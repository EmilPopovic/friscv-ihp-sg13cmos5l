TOP = friscv_soc_top

sources.f: ../../Bender.yml ../../Bender.lock $(wildcard src/*.sv)
	bender script flist-plus -t rtl -t synthesis > $@
	sed -i '\|/tech_cells_generic-[^/]*/src/rtl/tc_sram\.sv$$|d' $@
	sed -i '\|/tech_cells_generic-[^/]*/src/rtl/tc_clk\.sv$$|d' $@
	sed -i '\|/opentitan_peripherals-[^/]*/src/spi_host/rtl/|d' $@
	echo "$(CURDIR)/src/stubs/RM_IHPSG13_1P_1024x32_c2_bm_bist.sv" >> $@
	echo "$(CURDIR)/src/stubs/sg13cmos5l_stdcell_stubs.sv" >> $@
	echo "$(CURDIR)/src/stubs/sg13cmos5l_io_stubs.v" >> $@
	echo "$(CURDIR)/src/tc_sram.sv" >> $@
	echo "$(CURDIR)/src/stubs/tc_clk.sv" >> $@

.PHONY: area
area: sources.f
	rm -f area.rpt synth.log
	set -o pipefail; yosys -m slang -c synth.tcl 2>&1 | tee synth.log

.PHONY: librelane
librelane: sources.f
	librelane librelane/config.yaml --pdk ${PDK} --pdk-root ${PDK_ROOT} --manual-pdk

.PHONY: librelane-openroad
librelane-openroad:
	librelane librelane/config.yaml --pdk ${PDK} --pdk-root ${PDK_ROOT} --manual-pdk --last-run --flow OpenInOpenRoad

.PHONY: librelane-klayout
librelane-klayout:
	librelane librelane/config.yaml --pdk ${PDK} --pdk-root ${PDK_ROOT} --manual-pdk --last-run --flow OpenInKLayout

.PHONY: clean
clean:
	rm -f sources.f area.rpt synth.log
