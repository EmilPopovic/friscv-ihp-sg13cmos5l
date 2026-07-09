sources.f: ../../Bender.yml ../../Bender.lock
	bender script flist-plus -t rtl -t synthesis > $@

.PHONY: area
area: sources.f
	yosys -m slang -c synth.tcl

.PHONY: clean
clean:
	rm -f sources.f area.rpt
