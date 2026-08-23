.PHONY: sim
sim:
	make -C target/sim all

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
