TRELLIS?=/usr/share/trellis
TOOL?=
#TOOL?=/opt/riscv32i/bin

COMPILER?=riscv64-elf-

PROJECT=picosoc
LPF=i5.lpf

GATEWARE_DIR=gateware
GATEWARE_BUILD_DIR=$(GATEWARE_DIR)/build
JSON=$(GATEWARE_BUILD_DIR)/$(PROJECT).json
CONFIG=$(GATEWARE_BUILD_DIR)/$(PROJECT).config
BIT=$(GATEWARE_BUILD_DIR)/$(PROJECT).bit


SOC_DIR=$(GATEWARE_DIR)/picosoc/rtl
SOC_SRCS=$(wildcard $(SOC_DIR)/*.v)

SDRAM_MODULE_DIR=$(GATEWARE_DIR)/sdram_wb/rtl
SDRAM_MODULE_SRCS=$(wildcard $(SDRAM_MODULE_DIR)/*.v)

LCD_MODULE_DIR=$(GATEWARE_DIR)/rgblcd/rtl
LCD_MODULE_SRCS=$(wildcard $(LCD_MODULE_DIR)/*.v)

CAMERA_MODULE_DIR=$(GATEWARE_DIR)/camera/rtl
CAMERA_MODULE_SRCS=$(wildcard $(CAMERA_MODULE_DIR)/*.v)

GATEWARE_SRCS=$(SOC_SRCS) $(SDRAM_MODULE_SRCS) $(LCD_MODULE_SRCS)

PICOSOC_TB=$(GATEWARE_DIR)/picosoc/tb/picosoc_tb.v

FIRMWARE?=mem_test
SRC_DIR=firmware/$(FIRMWARE)/src
BUILD_DIR=firmware/$(FIRMWARE)/build

SRCS=$(wildcard $(SRC_DIR)/*.s) $(wildcard $(SRC_DIR)/*.c)
LINKER_SCRIPT=firmware/$(FIRMWARE)/sections.lds
ELF=$(BUILD_DIR)/firmware.elf
BIN=$(BUILD_DIR)/firmware.bin
HEX=$(BUILD_DIR)/firmware.hex

############
# firmware #
############

$(ELF): $(LINKER_SCRIPT) $(SRCS) 
	$(COMPILER)gcc -march=rv32im -mabi=ilp32 -Wl,-Bstatic,-T,$(LINKER_SCRIPT),--strip-debug -ffreestanding -nostdlib -o $(ELF) $(SRCS)
	$(COMPILER)objdump --disassemble $(ELF) > $(BUILD_DIR)/disassemble.out
#	$(TOOL)/riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -Wl,-Bstatic,-T,$(LINKER_SCRIPT),--strip-debug -ffreestanding -nostdlib -o $(ELF) $(SRCS)
#	$(TOOL)/riscv64-unknown-elf-objdump --disassemble $(ELF) > $(BUILD_DIR)/disassemble.out
#	riscv64-unknown-elf-gcc.exe -march=rv32i -mabi=ilp32 -Wl,-Bstatic,-T,$(LINKER_SCRIPT),--strip-debug -ffreestanding -nostdlib -o $(ELF) $(SRCS)

$(BIN): $(ELF)
	$(COMPILER)objcopy -O binary $(ELF) $(BIN)
#	$(TOOL)/riscv64-unknown-elf-objcopy -O binary $(ELF) $(BIN)
#	riscv64-unknown-elf-objcopy.exe -O binary $(ELF) $(BIN)

$(HEX): $(BIN)
	python3 makehex.py $^ 4096 > $@
#	$(TOOL)/riscv32-unknown-elf-objcopy -O verilog $(ELF) $(HEX)

firmware: $(HEX)
	cp $(HEX) ./

###########
# picosoc #
###########

### picosoc testbench
picosoc_tb.vvp: $(PICOSOC_TB) $(GATEWARE_SRCS)
	iverilog -Wall -Wno-portbind -Wno-timescale -DSIM=1 -s testbench -o $@ $^

picosoc_sim: picosoc_tb.vvp firmware.hex
	vvp -N $<

### picosoc
$(JSON): $(GATEWARE_SRCS) firmware.hex
	yosys -p "synth_ecp5 -json $@ -top top" -l $(GATEWARE_BUILD_DIR)/yosys-$(PROJECT).log $(GATEWARE_SRCS)

$(CONFIG): $(JSON) $(LPF)
	nextpnr-ecp5 --json $(JSON) --lpf $(LPF) --textcfg $@ --25k --freq 50 --package CABGA381 --speed 6 --log $(GATEWARE_BUILD_DIR)/nextpnr-$(PROJECT).log

$(BIT): $(CONFIG)
	#ecppack --svf-rowsize 100000 --svf picosoc.svf $< $@
	ecppack --compress --input $< --bit $@

%.svf: %.bit


############
# sdram_wb #
############



############
# sdram_fb #
############



#######
# lcd #
#######





###########
# support #
###########

clean:
	rm $(BUILD_DIR)/*
	rm ./*.hex
	rm $(GATEWARE_BUILD_DIR)/*

prog: $(BIT)
#	ecpprog -S $<
	ecpdap program --freq 5000 $<

calcpll:
#	ecppll -i 25 -o 100 -f pll.v --clkin_name clk --clkout0_name clk100M  --clkout1 100 --clkout1_name clk100M180 --phase1 180 --clkout2 50 --clkout2_name clk50M --phase2 0 
#	ecppll -i 25 -o 9 -f pll2.v --clkin_name clk --clkout0_name clk9
	ecppll -i 25 -o 100 -f pll.v --clkin_name clk --clkout0_name clk100M  --clkout1 100 --clkout1_name clk100M180 --phase1 180 --clkout2 50 --clkout2_name clk50M --phase2 0 --clkout3 9 --clkout3_name clk9 --phase3 0
#	ecppll -i 25 -o 100 -f pll.v --clkin_name clk --clkout0_name clk100M  --clkout1 100 --clkout1_name clk100M180 --phase1 180 --clkout2 50 --clkout2_name clk50M --phase2 0

.PHONY: picosoc_sim clean prog
.PRECIOUS: picosoc.json picosoc_out.config picosoc.bit
