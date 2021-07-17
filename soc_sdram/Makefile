TRELLIS?=/usr/share/trellis

firmware.elf: sections.lds start.s firmware.c 
	riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -Wl,-Bstatic,-T,sections.lds,--strip-debug -ffreestanding -nostdlib -o firmware.elf start.s firmware.c

firmware.bin: firmware.elf
	riscv64-unknown-elf-objcopy -O binary firmware.elf /dev/stdout > firmware.bin

firmware.hex: firmware.bin
	python3 makehex.py $^ 4096 > $@

attosoc_tb.vvp: attosoc_tb.v attosoc.v picorv32.v simpleuart.v sdram_wb.v lcd.v
	iverilog -Wall -Wno-portbind -Wno-timescale -DSIM=1 -s testbench -o $@ $^

attosoc_sim: attosoc_tb.vvp firmware.hex
	vvp -N $<

attosoc.json: top.v attosoc.v picorv32.v pll.v sdram_wb.v lcd.v pll9m.v firmware.hex
	yosys -p "synth_ecp5 -json $@ -top top" -l "yosys.log" top.v pll.v attosoc.v picorv32.v simpleuart.v sdram_wb.v lcd.v pll9m.v

attosoc_out.config: attosoc.json ecp5evn.lpf
	nextpnr-ecp5 --json attosoc.json --lpf ecp5evn.lpf --textcfg $@ --25k --freq 50 --package CABGA381 --speed 6 --log nextpnr-ecp5.log

attosoc.bit: attosoc_out.config
	#ecppack --svf-rowsize 100000 --svf attosoc.svf $< $@
	ecppack --compress --input $< --bit $@

%.svf: %.bit

prog: attosoc.bit
#	ecpprog -S $<
	ecpdap program --freq 5000 $<

calcpll:
#	ecppll -i 25 -o 100 -f pll.v --clkin_name clk --clkout0_name clk100M  --clkout1 100 --clkout1_name clk100M180 --phase1 180 --clkout2 50 --clkout2_name clk50M --phase2 0 
#	ecppll -i 25 -o 9 -f pll2.v --clkin_name clk --clkout0_name clk9
	ecppll -i 25 -o 100 -f pll.v --clkin_name clk --clkout0_name clk100M  --clkout1 100 --clkout1_name clk100M180 --phase1 180 --clkout2 50 --clkout2_name clk50M --phase2 0 --clkout3 9 --clkout3_name clk9 --phase3 0
#	ecppll -i 25 -o 100 -f pll.v --clkin_name clk --clkout0_name clk100M  --clkout1 100 --clkout1_name clk100M180 --phase1 180 --clkout2 50 --clkout2_name clk50M --phase2 0

.PHONY: attosoc_sim clean prog
.PRECIOUS: attosoc.json attosoc_out.config attosoc.bit
