sources.f: ../../Bender.yml ../../Bender.lock src/tc_sram.sv src/RM_IHPSG13_1P_1024x32_c2_bm_bist.sv
	bender script flist-plus -t rtl -t synthesis > $@
	sed -i '\|/tech_cells_generic-[^/]*/src/rtl/tc_sram\.sv$$|d' $@
	echo "$(CURDIR)/src/RM_IHPSG13_1P_1024x32_c2_bm_bist.sv" >> $@
	echo "$(CURDIR)/src/tc_sram.sv" >> $@

.PHONY: area
area: sources.f
	rm -f area.rpt synth.log
	set -o pipefail; yosys -m slang -c synth.tcl 2>&1 | tee synth.log

.PHONY: clean
clean:
	rm -f sources.f area.rpt synth.log
