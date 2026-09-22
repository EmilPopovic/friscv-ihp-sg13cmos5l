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

# sv2v front-end to produce a single Verilog file
SV2V_DIR     = build
SV2V_FLIST   = $(SV2V_DIR)/sv2v.f
SV2V_OUT     = $(SV2V_DIR)/$(TOP).v
SV2V_DEFINES = FUNCTIONAL TARGET_ASIC SYNTHESIS VERILATOR

# Fix files so sv2v can parse them
SV2V_FIX_AXI_PKG     = -e '/typedef shortint unsigned SU;/d' -e "s/return SU'(/return shortint'(/"
SV2V_FIX_OBI_UART_RX = -E -e '/^\s*\.(FALL_THROUGH|dtype)\s*\(\),?\s*$$/d' -e '/^\s*\.ADDR_DEPTH\s*\(\)/d'
SV2V_FIX_APB_TO_OBI  = -e '/assign obi_req_o\.rready = 1.b1;/d'
SV2V_FIX_HB_W2PHY    = -E -e 's/for \(int ([ij])=0; \1<byte_idx_q; \1\+\+\)/for (int \1=0; \1<NumAxiBytes; \1++) if (\1<byte_idx_q)/'
SV2V_FIX_OBI_UART_TX = -e 's/for (int i = 0; i <= word_len_bits; i = i + 1) begin/for (int i = 0; i < 8; i = i + 1) if (i <= word_len_bits) begin/'

define sv2v_fix
	@f=$$(grep -E '$(1)' $@) && [ -n "$$f" ] || { echo "ERROR: sv2v fixup: $(1) not in flist"; exit 1; }; \
	out=$(CURDIR)/$(SV2V_DIR)/patched/$$(basename $$f); \
	sed $(2) $$f > $$out; \
	if cmp -s $$f $$out; then echo "ERROR: sv2v fixup for $$(basename $$f) changed nothing"; exit 1; fi; \
	sed -i "s|^$$f$$|$$out|" $@
endef

$(SV2V_FLIST): sources.f
	@rm -rf $(SV2V_DIR)/patched
	@mkdir -p $(SV2V_DIR)/patched
	grep -v -E '/src/stubs/(RM_|delay_line_|sg13cmos5l_)|/deprecated/fifo_v[12]\.sv$$' $< > $@
	$(call sv2v_fix,/axi-[^/]*/src/axi_pkg\.sv$$,$(SV2V_FIX_AXI_PKG))
	$(call sv2v_fix,/pulp_obi_uart/rtl/obi_uart_rx\.sv$$,$(SV2V_FIX_OBI_UART_RX))
	$(call sv2v_fix,/obi-[^/]*/src/apb_to_obi\.sv$$,$(SV2V_FIX_APB_TO_OBI))
	$(call sv2v_fix,/pulp_hyperbus/src/hyperbus_w2phy\.sv$$,$(SV2V_FIX_HB_W2PHY))
	$(call sv2v_fix,/pulp_obi_uart/rtl/obi_uart_tx\.sv$$,$(SV2V_FIX_OBI_UART_TX))

# Always rerun sv2v
.PHONY: sv2v
sv2v: $(SV2V_FLIST)
	sv2v $$(sed -e 's/^+incdir+/-I/' -e 's/^+define+/-D/' $(SV2V_FLIST)) \
	    $(addprefix -D,$(SV2V_DEFINES)) src/$(TOP).sv --top $(TOP) \
	    -w $(SV2V_OUT) 2> $(SV2V_DIR)/sv2v.log || { cat $(SV2V_DIR)/sv2v.log; exit 1; }

.PHONY: area
area: $(PDK_STAMP) sv2v
	rm -f area.rpt
	$(LIBRELANE) --run-tag $(AREA_RUN_TAG) --overwrite --to Yosys.Synthesis
	netlist=$$(echo $(AREA_RUN_DIR)/*-yosys-synthesis/$(TOP).nl.v); \
	yosys -p "read_verilog -sv $$netlist; stat $(foreach lib,$(AREA_LIBERTIES),-liberty $(lib))" | tee area.rpt

.PHONY: librelane
librelane: $(PDK_STAMP) sv2v
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
	rm -rf $(AREA_RUN_DIR) $(PDK_DIR) $(SV2V_DIR)
