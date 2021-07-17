#
# TESTBENCH makefile
#

TRELLIS?=/usr/share/trellis
ECP5_LIBS ?= $(shell yosys-config --datdir/ecp5/cells_sim.v)
RTL_DIR ?= ../rtl
TB_SRC ?= $(RTL_DIR)/dpram.v $(RTL_DIR)/sdram_burst.v

%_tb: %_tb.v $(ECP5_LIBS) $(TB_SRC)
	iverilog -Wall -Wno-portbind -Wno-timescale -DSIM=1 -o $(notdir $@) $(TB_SRC) $<

%_tb.vcd: %_tb
	vvp -N $(notdir $<) +vcd=$(notdir $@)


clean:
	rm -f *.vcd

.PHONY: clean

