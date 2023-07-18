# icebreaker.mk - Xosera for iCEBreaker FPGA board
# vim: set noet ts=8 sw=8

# Using icestorm tools + yosys + nextpnr
# Modified from examples in icestorm distribution for
# up5k_vga by E. Brombaugh (emeb) and further extensively
# hacked by Xark for Xosera purposes

# Primary tools (official binaries available from https://github.com/YosysHQ/oss-cad-suite-build/releases/latest)
#       Yosys
#       nextpnr-ice40
#       Verilator               (optional)
#       Icarus Verilog          (optional)
#       Built using macOS and GNU/Linux Ubuntu distribution

# Makefile "best practices" from https://tech.davis-hansson.com/p/make/ (but not forcing gmake)
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

# Version bookkeeping
BUILDDATE := $(shell date -u "+%Y%m%d")
XOSERA_HASH := $(shell git rev-parse --short HEAD)
DIRTYFILES := $(shell git status --porcelain --untracked-files=no | grep rtl/ | grep -v _stats.txt | cut -d " " -f 3-)
ifeq ($(strip $(DIRTYFILES)),)
# "clean" (unmodified) from git
XOSERA_CLEAN := 1
$(info === Xosera iCEBreaker [$(XOSERA_HASH)] is CLEAN from git)
else
# "dirty" (HDL modified) from git
XOSERA_CLEAN := 0
$(info === Xosera iCEBreaker [$(XOSERA_HASH)] is DIRTY: $(DIRTYFILES))
endif

# Set default FPGA config number (if not set)
FPGA_CONFIG ?= 0

# Maximum number of CPU cores to use before waiting with FMAX_TEST
MAX_CPUS ?= 8

# Xosera video mode selection:
# Supported modes:                           (exact) (actual)
#       MODE_640x400    640x400@70Hz    clock 25.175 (25.125) MHz
#       MODE_640x480    640x480@60Hz    clock 25.175 (25.125) MHz
#       MODE_640x480_75 640x480@75Hz    clock 31.500 (31.500) MHz
#       MODE_640x480_85 640x480@85Hz    clock 36.000 (36.000) MHz
#       MODE_720x400    720x400@70Hz    clock 28.322 (28.500) MHz
#       MODE_848x480    848x480@60Hz    clock 33.750 (33.750) MHz (16:9 480p)
#       MODE_800x600    800x600@60Hz    clock 40.000 (39.750) MHz
#       MODE_1024x768   1024x768@60Hz   clock 65.000 (65.250) MHz [fails timing]
#       MODE_1280x720   1280x720@60Hz   clock 74.176 (73.500) MHz [fails timing]
VIDEO_MODE ?= MODE_848x480

# Xosera video output selection:
# Supported video outputs:
#   PMOD_1B2_DVI12              12-bit DVI, PMOD 1A&1B  https://1bitsquared.com/products/pmod-digital-video-interface
#   PMOD_DIGILENT_VGA           12-bit VGA, PMOD 1A&1B  https://store.digilentinc.com/pmod-vga-video-graphics-array/
#   PMOD_XESS_VGA                9-bit VGA, PMOD 1A&1B  http://www.xess.com/shop/product/stickit-vga/
#   PMOD_XESS_VGA_SINGLE         6-bit VGA, PMOD 1B     http://www.xess.com/shop/product/stickit-vga/ (half used)
VIDEO_OUTPUT ?= PMOD_1B2_DVI12

VERILOG_DEFS := -D$(VIDEO_MODE) -D$(VIDEO_OUTPUT)

ifeq ($(strip $(VIDEO_OUTPUT)), PMOD_1B2_DVI12)
VMODENAME := dvi
else
VMODENAME := vga
endif

PFB ?= true

ifneq ($(strip $(PF_B)),)
VERILOG_DEFS += -DEN_PF_B
endif

AUDIO ?= 0

SPI_INTERFACE ?= true

ifeq ($(strip $(AUDIO)),0)
OUTSUFFIX := $(VMODENAME)_$(subst MODE_,,$(VIDEO_MODE))
else
VERILOG_DEFS += -DEN_AUDIO=$(AUDIO)
OUTSUFFIX := aud$(AUDIO)_$(VMODENAME)_$(subst MODE_,,$(VIDEO_MODE))
endif

FONTFILES := $(wildcard tilesets/*.mem)

# RTL source and include directory
SRCDIR := .

# log output directory
LOGS := icebreaker/logs

# Xosera project setup for iCEBreaker FPGA
TOP := xosera_iceb
PIN_DEF := icebreaker/icebreaker.pcf
DEVICE := up5k
PACKAGE := sg48

# Verilog source directories
VPATH := $(SRCDIR) icebreaker

# Verilog source files for design
SRC := icebreaker/$(TOP).sv $(wildcard $(SRCDIR)/*.sv)

# Verilog include files for design
INC := $(wildcard $(SRCDIR)/*.svh)

# dot graphic diagram files
DOT := $(SRC:.sv=.dot)

# icestorm tools
YOSYS := yosys
YOSYS_CONFIG := yosys-config
ICEPACK := icepack
ICETIME := icetime
ICEPROG := iceprog
ICEMULTI := icemulti

# Yosys generic arguments
YOSYS_ARGS := -e "no driver" -w "tri-state" -w "list of registers"

# Yosys synthesis arguments
FLOW3 :=
#YOSYS_SYNTH_ARGS := -device u -retime -top $(TOP)
#YOSYS_SYNTH_ARGS := -device u -abc2 -relut -retime -top $(TOP)
#YOSYS_SYNTH_ARGS := -device u -abc9 -relut -top $(TOP)
#YOSYS_SYNTH_ARGS := -device u -no-rw-check -abc2 -top $(TOP)
YOSYS_SYNTH_ARGS := -device u -no-rw-check -dff -abc9 -top $(TOP)
#FLOW3 := ; scratchpad -copy abc9.script.flow3 abc9.script

# Verilog preprocessor definitions common to all modules
DEFINES := -DNO_ICE40_DEFAULT_ASSIGNMENTS -DGITCLEAN=$(XOSERA_CLEAN) -DGITHASH=$(XOSERA_HASH) -DBUILDDATE=$(BUILDDATE) -DFPGA_CONFIG=$(FPGA_CONFIG) $(VERILOG_DEFS) -DICE40UP5K -DICEBREAKER
ifneq ($(strip $(SPI_INTERFACE)),)
DEFINES += -DSPI_INTERFACE
endif

TECH_LIB := $(shell $(YOSYS_CONFIG) --datdir/ice40/cells_sim.v)
VLT_CONFIG := icebreaker/ice40_config.vlt

# Verilator tool (used for "lint")
VERILATOR := verilator
VERILATOR_ARGS := --sv --language 1800-2012 -I$(SRCDIR) -v $(TECH_LIB) $(VLT_CONFIG) -Werror-UNUSED -Wall -Wno-DECLFILENAME

# nextPNR tools
NEXTPNR := nextpnr-ice40
NEXTPNR_ARGS :=  --randomize-seed --promote-logic --opt-timing --placer heap

OUTNAME := $(TOP)_$(OUTSUFFIX)

# defult target is make bitstream
all: icebreaker/$(OUTNAME).bin $(MAKEFILE_LIST)
	@echo === Finished Building iCEBreaker Xosera: $(VIDEO_OUTPUT) $(SPI_INTERFACE) ===
.PHONY: all

# program iCEBreaker FPGA via USB (may need udev rules or sudo on Linux)
prog: icebreaker/$(OUTNAME).bin $(MAKEFILE_LIST)
	@echo === Programming iCEBreaker Xosera: $(VIDEO_OUTPUT) $(SPI_INTERFACE) ===
	$(ICEPROG) -d i:0x0403:0x6010 $(TOP).bin
.PHONY: prog

# run icetime to generate a timing report
timing: icebreaker/$(OUTNAME).rpt $(MAKEFILE_LIST)
	@echo iCETime timing report: $(TOP).rpt
.PHONY: timing

# run Yosys to generate a "dot" graphical representation of each design file
show: $(DOT) $(MAKEFILE_LIST)
.PHONY: show

# run Yosys with "noflatten", which will produce a resource count per module
count: $(SRC) $(INC) $(FONTFILES) $(MAKEFILE_LIST)
	@mkdir -p $(LOGS)
	@-cp $(LOGS)/$(OUTNAME)_yosys_count.log $(LOGS)/$(OUTNAME)_yosys_count_last.log
	$(YOSYS) $(YOSYS_ARGS) -l $(LOGS)/$(OUTNAME)_yosys_count.log -q -p 'verilog_defines $(DEFINES) ; read_verilog -I$(SRCDIR) -sv $(SRC) $(FLOW3) ; synth_ice40 $(YOSYS_SYNTH_ARGS) -noflatten'
.PHONY: count

# run Verilator to check for Verilog issues
lint: $(VLT_CONFIG) $(SRC) $(INC) $(FONTFILES) $(MAKEFILE_LIST)
	$(VERILATOR) $(VERILATOR_ARGS) --lint-only $(DEFINES) --top-module $(TOP) $(SRC)
.PHONY: lint

$(DOT): %.dot: %.sv $(MAKEFILE_LIST)
	mkdir -p icebreaker/dot $(@D)
	$(YOSYS) $(YOSYS_ARGS) -l $(LOGS)/$(OUTNAME)_yosys.log -q -p 'verilog_defines $(DEFINES) -DSHOW ; read_verilog -I$(SRCDIR) -sv $< ; show -enum -stretch -signed -width -prefix upduino/dot/$(basename $(notdir $<)) $(basename $(notdir $<))'

# synthesize Verilog and create json description
%.json: $(VLT_CONFIG) $(SRC) $(INC) $(FONTFILES) $(MAKEFILE_LIST)
	@echo === Building iCEBreaker Xosera ===
	@rm -f $@
	@mkdir -p $(LOGS) $(@D)
	$(VERILATOR) $(VERILATOR_ARGS) --lint-only $(DEFINES) --top-module $(TOP) $(SRC) 2>&1 | tee $(LOGS)/$(OUTNAME)_verilator.log
	$(YOSYS) $(YOSYS_ARGS) -l $(LOGS)/$(OUTNAME)_yosys.log -q -p 'verilog_defines $(DEFINES) ; read_verilog -I$(SRCDIR) -sv $(SRC) $(FLOW3) ; synth_ice40 $(YOSYS_SYNTH_ARGS) -json $@'
	@-grep "XOSERA" $(LOGS)/$(OUTNAME)_yosys.log
	@-grep "\(Number of cells\|Number of wires\)" $(LOGS)/$(OUTNAME)_yosys.log

# make ASCII bitstream from JSON description and device parameters
icebreaker/%_$(OUTSUFFIX).asc: icebreaker/%_$(OUTSUFFIX).json $(PIN_DEF) $(MAKEFILE_LIST)
	@-rm -f $@
	@mkdir -p $(LOGS) $(@D)
	@-cp $(OUTNAME)_stats.txt $(LOGS)/$(OUTNAME)_stats_last.txt
ifdef FMAX_TEST	# run nextPNR FMAX_TEST times to determine "Max frequency" range
	@echo === Synthesizing $(FMAX_TEST) bitstreams for best fMAX
	@echo $(NEXTPNR) -l $(LOGS)/$(OUTNAME)_nextpnr.log -q $(NEXTPNR_ARGS) --$(DEVICE) --package $(PACKAGE) --json $< --pcf $(PIN_DEF) --asc $@
	@mkdir -p $(LOGS)/fmax
	@-rm -f $(LOGS)/fmax/*
	@-cp $< $(LOGS)/fmax
	@num=1 ; while [[ $$num -le $(FMAX_TEST) ]] ; do \
	  ( \
	    $(NEXTPNR) -l "$(LOGS)/fmax/$(OUTNAME)_$${num}_nextpnr.log" -q --timing-allow-fail $(NEXTPNR_ARGS) --$(DEVICE) --package $(PACKAGE) --json $< --pcf $(PIN_DEF) --asc $(LOGS)/fmax/$(OUTNAME)_$${num}.asc ; \
	    grep "Max frequency" $(LOGS)/fmax/$(OUTNAME)_$${num}_nextpnr.log | tail -1 | cut -d " " -f 2- ; \
	  ) & \
	  pids[$${num}]=$$! ; \
	  ((num = num + 1)) ; \
	  if ((num > ($(MAX_CPUS) - 1))) ; then \
	    if ((num % $(MAX_CPUS) == ($(MAX_CPUS) - 1))); then \
	      ((wnum = num - $(MAX_CPUS))) ; \
	      wait $${pid[wnum]} ; \
	    fi ; \
	  fi ; \
	done ; \
	wait
	@num=1 ; while [[ $$num -le $(FMAX_TEST) ]] ; do \
	  grep "Max frequency" $(LOGS)/fmax/$(OUTNAME)_$${num}_nextpnr.log | tail -1 | cut -d " " -f 7 >"$(LOGS)/fmax/fmax_temp.txt" ; \
	  FMAX=$$(cat "$(LOGS)/fmax/fmax_temp.txt") ; \
	  echo $${num} $${FMAX} "$(LOGS)/fmax/$(OUTNAME)_$${num}.asc" >> $(LOGS)/fmax/$(OUTNAME)_list.log ; \
	  ((num = num + 1)) ; \
	done
	@echo === fMAX after $(FMAX_TEST) runs: ===
	@awk '{ total += $$2 ; minv = (minv == 0 || minv > $$2 ? $$2 : minv) ; maxv = (maxv < $$2 ? $$2 : maxv) ; count++ } END \
	  { print "fMAX: Minimum frequency:", minv ; print "fMAX: Average frequency:", total/count ; print "fMAX: Maximum frequency:", maxv, "   <== selected as best" ; }' $(LOGS)/fmax/$(OUTNAME)_list.log
	@echo === fMAX after $(FMAX_TEST) runs: === > $(LOGS)/$(OUTNAME)_fmax.txt
	@awk '{ total += $$2 ; minv = (minv == 0 || minv > $$2 ? $$2 : minv) ; maxv = (maxv < $$2 ? $$2 : maxv) ; count++ } END \
	  { print "fMAX: Minimum frequency:", minv ; print "fMAX: Average frequency:", total/count ; print "fMAX: Maximum frequency:", maxv, "   <== selected as best" ; }' $(LOGS)/fmax/$(OUTNAME)_list.log >> $(LOGS)/$(OUTNAME)_fmax.txt
	@awk '{ if (maxv < $$2) { best = $$1 ; maxv = $$2 ; } ; } END { print best, maxv ; }' $(LOGS)/fmax/$(OUTNAME)_list.log  > "$(LOGS)/fmax/fmax_temp.txt"
	@BEST=$$(cut -d " " -f1 "$(LOGS)/fmax/fmax_temp.txt") FMAX=$$(cut -d " " -f2 "$(LOGS)/fmax/fmax_temp.txt") ; \
	  cp "$(LOGS)/fmax/$(OUTNAME)_$${BEST}_nextpnr.log" "$(LOGS)/$(OUTNAME)_nextpnr.log" ; \
	  cp "$(LOGS)/fmax/$(OUTNAME)_$${BEST}.asc" $@
	@rm "$(LOGS)/fmax/fmax_temp.txt"
else
ifdef NO_PNR_RETRY
	@echo NO_PNR_RETRY set, so failure IS an option...
	$(NEXTPNR) -l $(LOGS)/$(OUTNAME)_nextpnr.log -q $(NEXTPNR_ARGS) --$(DEVICE) --package $(PACKAGE) --json $< --pcf $(PIN_DEF) --asc $@
else
	@echo $(NEXTPNR) -l $(LOGS)/$(OUTNAME)_nextpnr.log -q $(NEXTPNR_ARGS) --$(DEVICE) --package $(PACKAGE) --json $< --pcf $(PIN_DEF) --asc $@
	@until $$($(NEXTPNR) -l $(LOGS)/$(OUTNAME)_nextpnr.log -q $(NEXTPNR_ARGS) --$(DEVICE) --package $(PACKAGE) --json $< --pcf $(PIN_DEF) --asc $@) ; do \
	  echo 'Retrying nextpnr-ice40 with new seed...' ; \
	done
endif
endif
	@echo === iCEBreaker Xosera: $(VIDEO_OUTPUT) $(VIDEO_MODE) $(SPI_INTERFACE) | tee $(OUTNAME)_stats.txt
	@-grep "XOSERA" $(LOGS)/$(OUTNAME)_yosys.log | tee -a $(OUTNAME)_stats.txt
	@-tabbyadm version | grep "Package" | tee -a $(OUTNAME)_stats.txt
	@$(YOSYS) -V 2>&1 | tee -a $(OUTNAME)_stats.txt
	@$(NEXTPNR) -V 2>&1 | tee -a $(OUTNAME)_stats.txt
	@sed -n '/Device utilisation/,/Info: Placed/p' $(LOGS)/$(OUTNAME)_nextpnr.log | sed '$$d' | grep -v ":     0/" | tee -a $(OUTNAME)_stats.txt
	@grep "Max frequency" $(LOGS)/$(OUTNAME)_nextpnr.log | tail -1 | tee -a $(OUTNAME)_stats.txt
	@-diff -U0 $(LOGS)/$(OUTNAME)_stats_last.txt $(OUTNAME)_stats.txt | grep -v "\(^@\|^+\|^---\)" | while read line; do echo "PREVIOUS: $$line" ; done >$(LOGS)/$(OUTNAME)_stats_delta.txt
	@-diff -U0 $(LOGS)/$(OUTNAME)_stats_last.txt $(OUTNAME)_stats.txt | grep -v "\(^@\|^+++\|^-\)" | while read line; do echo "CURRENT : $$line" ; done >>$(LOGS)/$(OUTNAME)_stats_delta.txt
	@echo
	@-cat $(LOGS)/$(OUTNAME)_stats_delta.txt

# make binary bitstream from ASCII bitstream
icebreaker/%_$(OUTSUFFIX).bin: icebreaker/%_$(OUTSUFFIX).asc $(MAKEFILE_LIST)
	@rm -f $@
	$(ICEPACK) $< $@
	$(ICEMULTI) -v -v -p0 icebreaker/*.bin -o $(TOP).bin

# make timing report from ASCII bitstream
icebreaker/%_$(OUTSUFFIX).rpt: icebreaker/%_$(OUTSUFFIX).asc $(MAKEFILE_LIST)
	@rm -f $@
	$(ICETIME) -d $(DEVICE) -m -t -r $@ $<

# disable warnings in cells_sim.v library for Verilator lint
$(VLT_CONFIG):
	@echo === Verilator cells_sim.v warning exceptions ===
	@echo >$(VLT_CONFIG)
	@echo >>$(VLT_CONFIG) \`verilator_config
	@echo >>$(VLT_CONFIG) lint_off -rule UNUSED    -file \"$(TECH_LIB)\"
	@echo >>$(VLT_CONFIG) lint_off -rule UNDRIVEN  -file \"$(TECH_LIB)\"
	@echo >>$(VLT_CONFIG) lint_off -rule WIDTH     -file \"$(TECH_LIB)\"

# delete all targets that will be re-generated
clean:
	rm -f $(VLT_CONFIG) xosera_iceb.bin $(wildcard icebreaker/*.json) $(wildcard icebreaker/*.asc) $(wildcard icebreaker/*.rpt) $(wildcard icebreaker/*.bin)
.PHONY: clean

# prevent make from deleting any intermediate files
.SECONDARY:
