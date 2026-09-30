.PHONY: sim
sim:
	make -C target/sim all

.PHONY: run-chip
run-chip:
	make -C target/sim test

.PHONY: run-soc
run-soc:
	make -C target/sim test-soc

.PHONY: run-gls
run-gls:
	make -C target/sim gls

.PHONY: run-jtag
run-jtag:
	make -C target/sim jtag

.PHONY: run-debug
run-debug:
	make -C target/sim debug

.PHONY: report-area
report-area:
	make -C target/ihp-sg13cmos5l area

.PHONY: librelane
librelane:
	make -C target/ihp-sg13cmos5l librelane

.PHONY: librelane-openroad
librelane-openroad:
	make -C target/ihp-sg13cmos5l librelane-openroad

.PHONY: librelane-klayout
librelane-klayout:
	make -C target/ihp-sg13cmos5l librelane-klayout

.PHONY: check-last
check-last:
	make -C target/ihp-sg13cmos5l check-last

.PHONY: clean
clean:
	make -C target/sim clean
	make -C target/ihp-sg13cmos5l clean
