sources.f: ../../../Bender.yml ../../../Bender.lock $(wildcard src/*.sv)
	bender script flist-plus -t rtl -t synthesis -t fpga -t xilinx > $@
	echo "$(CURDIR)/src/friscv_soc_pynq.sv" >> $@
