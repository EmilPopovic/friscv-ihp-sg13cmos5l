sources.f: ../../Bender.yml ../../Bender.lock
	bender script flist-plus -t rtl -t synthesis > $@

.PHONY: area
area: sources.f
	rm -f area.rpt synth.log
	set -o pipefail; yosys -m slang -c synth.tcl 2>&1 | tee synth.log

.PHONY: clean
clean:
	rm -f sources.f area.rpt synth.log
