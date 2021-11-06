/*
 *  ECP5 PicoRV32 demo
 *
 *  Copyright (C) 2017  Clifford Wolf <clifford@clifford.at>
 *  Copyright (C) 2018  David Shah <dave@ds0.me>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

`ifdef PICORV32_V
`error "picosoc.v must be read before picorv32.v!"
`endif

`define PICORV32_REGS picosoc_regs

module picosoc (
	input              clk,

	// LEDs
	output reg         led,

	// UART signals
	output             uart_tx,
	input              uart_rx,

	// SDRAM signals
	input  wire [31:0] sdram_dq_i,
	output wire [31:0] sdram_dq_o,
	output wire [10:0] sdram_addr,
	output wire [1:0]  sdram_ba,

	output wire        sdram_we_n,
	output wire        sdram_cas_n,
	output wire        sdram_ras_n,
	output wire        sdram_clk,

    // LCD connections
	output wire        LCD_CLK,
	output wire        LCD_HYNC,
	output wire        LCD_SYNC,
	output wire        LCD_DEN,
	output wire        [4:0] LCD_R,
	output wire        [5:0] LCD_G,
	output wire        [4:0] LCD_B,
	
	input  wire        clk100M,
	input  wire        clk9M
);



	// Reset
	//======
	reg [5:0]          reset_cnt = 0;
	wire               resetn = &reset_cnt;
	wire               reset = ~resetn;

	always @(posedge clk) begin
		reset_cnt <= reset_cnt + !resetn;
	end

	// RAM and load RAM
	//=================
	parameter integer  MEM_WORDS      = 8192;
	parameter [31:0]   STACKADDR      = 32'h 0000_0000 + (4*MEM_WORDS);       // end of memory
	parameter [31:0]   PROGADDR_RESET = 32'h 0000_0000;                       // start of memory

	reg [31:0]         ram [0:MEM_WORDS-1];
	reg [31:0]         ram_rdata;
	reg                ram_ready;

	initial $readmemh("firmware.hex", ram);


	// Framebuffers
	//=============
	reg [31:0]         fb_write_buffer [0:255];
	reg [31:0]         fb_write_buffer_rdata;
	reg                fb_write_buffer_ready;
	wire               fb_write_buffer_sel;


	reg [31:0]         fb_line_buffer [0:255];
	reg [31:0]         fb_line_buffer_rdata;
	reg                fb_line_buffer_ready;
	wire               fb_line_buffer_sel;



	// RISCRV32 interface
	//===================
	wire        mem_valid;
	wire        mem_instr;
	wire        mem_ready;
	wire [31:0] mem_addr;
	wire [31:0] mem_wdata;
	wire [3:0]  mem_wstrb;
	wire [31:0] mem_rdata;

	wire        mem_la_read;
	wire        mem_la_write;
	wire [31:0] mem_la_addr;
	wire [31:0] mem_la_wdata;
	wire [ 3:0] mem_la_wstrb;


	// RAM interface
	//==============
	always @(posedge clk) begin
		ram_ready <= 1'b0;
		if (mem_addr[31:24] == 8'h00 && mem_valid) begin
			if (mem_wstrb[0]) ram[mem_addr[23:2]][7:0] <= mem_wdata[7:0];
			if (mem_wstrb[1]) ram[mem_addr[23:2]][15:8] <= mem_wdata[15:8];
			if (mem_wstrb[2]) ram[mem_addr[23:2]][23:16] <= mem_wdata[23:16];
			if (mem_wstrb[3]) ram[mem_addr[23:2]][31:24] <= mem_wdata[31:24];

			ram_rdata <= ram[mem_addr[23:2]];
			ram_ready <= 1'b1;
		end
    end


	// FRAMEBUFFER: WRITE BUFFER (0x0500_00xx)
	//========================================
	assign fb_write_buffer_sel = mem_valid && (mem_addr[31:24] == 8'h05);

	always @(posedge clk) begin
		fb_write_buffer_ready <= 1'b0;
		if (fb_write_buffer_sel) begin
			if (mem_wstrb[0]) fb_write_buffer[ mem_addr[23:2] ][7:0]   <= mem_wdata[7:0];
			if (mem_wstrb[1]) fb_write_buffer[ mem_addr[23:2] ][15:8]  <= mem_wdata[15:8];
			if (mem_wstrb[2]) fb_write_buffer[ mem_addr[23:2] ][23:16] <= mem_wdata[23:16];
			if (mem_wstrb[3]) fb_write_buffer[ mem_addr[23:2] ][31:24] <= mem_wdata[31:24];

			fb_write_buffer_rdata <= fb_write_buffer[mem_addr[23:2]];
			fb_write_buffer_ready <= 1'b1;
		end
    end


	// FRAMEBUFFER: LINE BUFFER (0x0500_01xx)
	//=======================================
	assign fb_line_buffer_sel = mem_valid && (mem_addr[31:24] == 8'h06);

	always @(posedge clk) begin
		fb_line_buffer_ready <= 1'b0;
		if (fb_line_buffer_sel) begin
			if (mem_wstrb[0]) fb_line_buffer[ mem_addr[23:2] ][7:0]   <= mem_wdata[7:0];
			if (mem_wstrb[1]) fb_line_buffer[ mem_addr[23:2] ][15:8]  <= mem_wdata[15:8];
			if (mem_wstrb[2]) fb_line_buffer[ mem_addr[23:2] ][23:16] <= mem_wdata[23:16];
			if (mem_wstrb[3]) fb_line_buffer[ mem_addr[23:2] ][31:24] <= mem_wdata[31:24];

			fb_line_buffer_rdata <= fb_line_buffer[mem_addr[23:2]];
			fb_line_buffer_ready <= 1'b1;
		end
		else begin
			if (lcd_x[0] == 0)
				{lcd_red, lcd_grn, lcd_blu} <= fb_line_buffer[lcd_x[15:1]][15:0];
			else
				{lcd_red, lcd_grn, lcd_blu} <= fb_line_buffer[lcd_x[15:1]][31:16];
		end
    end

	// IO interface
	//=============
	wire         iomem_valid;
	reg          iomem_ready;
	wire [31:0]  iomem_addr;
	wire [31:0]  iomem_wdata;
	wire [3:0]   iomem_wstrb;
	wire [31:0]  iomem_rdata;

	assign iomem_valid = mem_valid && (mem_addr[31:24] == 8'h02);
	assign iomem_wstrb = mem_wstrb;
	assign iomem_addr  = mem_addr;
	assign iomem_wdata = mem_wdata;

	wire         simpleuart_reg_div_sel = mem_valid && (mem_addr == 32'h0200_0004);
	wire [31:0]  simpleuart_reg_div_do;
 
	wire         simpleuart_reg_dat_sel = mem_valid && (mem_addr == 32'h0200_0008);
	wire [31:0]  simpleuart_reg_dat_do;
	wire         simpleuart_reg_dat_wait;

	always @(posedge clk) begin
		iomem_ready <= 1'b0;
		if (iomem_valid && iomem_wstrb[0] && mem_addr == 32'h0200_0000) begin
			led <= iomem_wdata;
			iomem_ready <= 1'b1;
		end
	end


	// Timer
	//======
	reg [31:0]   tmr_reg;
	wire         tmr_valid;
	reg          tmr_ready;
	reg [31:0]  tmr_rdata;

	assign tmr_valid = mem_valid && (mem_addr[31:24] == 8'h04);

	always @(posedge clk) begin
		if (reset)
			tmr_reg = 32'h0000_0000;
		else begin
			tmr_ready <= 1'b0;
			if (tmr_valid) begin
				if (mem_wstrb[0]) tmr_reg[7:0]   <= mem_wdata[7:0];
				if (mem_wstrb[1]) tmr_reg[15:8]  <= mem_wdata[15:8];
				if (mem_wstrb[2]) tmr_reg[23:16] <= mem_wdata[23:16];
				if (mem_wstrb[3]) tmr_reg[31:24] <= mem_wdata[31:24];

				tmr_rdata <= tmr_reg;
				tmr_ready <= 1'b1;
			end
			else
				tmr_reg = tmr_reg + 1;
		end
	end

	// SDRAM begin
	//============
	// Wishbone Interface
	wire         sdram_sel;
	wire  [20:0] wb_addr;
	wire  [31:0] wb_wdata;
	wire  [31:0] wb_rdata;

	wire         wb_cyc;
	wire         wb_stb;
	wire         wb_we;

	wire         wb_ack;
	// wire         wb_ack_slow;		// only need this for ack (only valid for 1 clock cycle), rdata is latched
	// reg          wb_ack_fast_flag;
	// reg [2:0]    wb_ack_slow_sync;

	// always @(posedge clk100M) begin
	// 	wb_ack_fast_flag <= wb_ack_fast_flag ^ wb_ack_fast;
	// end

	// always @(posedge clk) begin
	// 	wb_ack_slow_sync <= {wb_ack_slow_sync[1:0], wb_ack_fast_flag};
	// end

	// assign wb_ack_slow = wb_ack_slow_sync[2] ^ wb_ack_slow_sync[1]; 

	sdram_wb sdram_wb_inst (
		.adr_i(wb_addr),
		.dat_i(wb_wdata),
		.cyc_i(wb_cyc),
		.stb_i(wb_stb),
		.we_i(wb_we),

		.dat_o(wb_rdata),
		.ack_o(wb_ack),

		.sdram_dq_i(sdram_dq_i),
		.sdram_dq_o(sdram_dq_o),
		.sdram_addr(sdram_addr),
		.sdram_ba(sdram_ba),

		.sdram_we_n(sdram_we_n),
		.sdram_cas_n(sdram_cas_n),
		.sdram_ras_n(sdram_ras_n),
		.sdram_clk(sdram_clk),

		.clk(clk100M),
		.rst(reset)
	);


	// Connect to picorv32 signals
	//----------------------------
	// mem_valid - core initiates memory transfer
	// mem_ready - core signals stays valid until peer asserts mem_ready
	// 
	// READ:
	// mem_wstrb - is 0
	// mem_wdata - not used
	// mem_addr  - address to read
	// mem_rdata - memory reads data at mem_addr, and places value on mem_rdata 
	//             in the cycle mem_ready is asserted
	// mem_ready - asserts when mem_rdata is valid
	//
	// WRITE:
	// mem_wstrb - is NOT 0: 1111 - 32 bytes, 1100 - MSB, 0011 - LSB, 1000 to 0001 - byte
	// mem_wdata - data to write to address mem_addr
	// mem_addr  - address to write to
	// mem_rdata - memory reads data at mem_addr, and places value on mem_rdata 
	//             in the cycle mem_ready is asserted
	// mem_ready - asserts when finish writing

	assign sdram_sel = mem_valid && (mem_addr[31:24] == 2'h03);	// 32'h0300_0000 - 32'h0310_0000
	assign wb_cyc    = sdram_sel;
	assign wb_stb    = sdram_sel;
	assign wb_we     = |mem_wstrb;
	assign wb_addr   = mem_addr[21:2];
	assign wb_wdata  = mem_wdata;
	// Assigned below (in the PICORV32 assignments section): assign mem_ready = wb_ack1;
	// Assigned below (in the PICORV32 assignments section): assign mem_rdata = wb_rdata;




	// PICORV32 assignments
	//=====================

	assign mem_ready = (iomem_valid && iomem_ready) 
					||  simpleuart_reg_div_sel 
					|| (simpleuart_reg_dat_sel && !simpleuart_reg_dat_wait) 
					|| (sdram_sel && wb_ack)
					||  tmr_ready
					|| 	ram_ready
					||  fb_write_buffer_ready
					||  fb_line_buffer_ready;

	assign mem_rdata = simpleuart_reg_div_sel ? simpleuart_reg_div_do 
					:  simpleuart_reg_dat_sel ? simpleuart_reg_dat_do 
					:  sdram_sel              ? wb_rdata
					:  tmr_valid              ? tmr_rdata
					:  fb_write_buffer_sel    ? fb_write_buffer_rdata
					:  fb_line_buffer_sel     ? fb_line_buffer_rdata
					:  ram_rdata;
	picorv32 #(
		.STACKADDR(STACKADDR),
		.PROGADDR_RESET(PROGADDR_RESET),
		.PROGADDR_IRQ(32'h 0000_0010),
		.BARREL_SHIFTER(0),
		.COMPRESSED_ISA(0),
		.ENABLE_MUL(0),
		.ENABLE_DIV(0),
		.ENABLE_IRQ(0),
		.ENABLE_IRQ_QREGS(0),
		.CATCH_MISALIGN(0),
		.CATCH_ILLINSN(0)
	) cpu (
		.clk         (clk        ),
		.resetn      (resetn     ),
		.mem_valid   (mem_valid  ),
		.mem_instr   (mem_instr  ),
		.mem_ready   (mem_ready  ),
		.mem_addr    (mem_addr   ),
		.mem_wdata   (mem_wdata  ),
		.mem_wstrb   (mem_wstrb  ),
		.mem_rdata   (mem_rdata  ),

		.mem_la_read (mem_la_read),
		.mem_la_write(mem_la_write),
		.mem_la_addr (mem_la_addr),
		.mem_la_wdata(mem_la_wdata),
		.mem_la_wstrb(mem_la_wstrb)

	);

	simpleuart simpleuart (
		.clk         (clk         ),
		.resetn      (resetn      ),

		.ser_tx      (uart_tx     ),
		.ser_rx      (uart_rx     ),

		.reg_div_we  (simpleuart_reg_div_sel ? mem_wstrb : 4'b 0000),
		.reg_div_di  (mem_wdata),
		.reg_div_do  (simpleuart_reg_div_do),

		.reg_dat_we  (simpleuart_reg_dat_sel ? mem_wstrb[0] : 1'b 0),
		.reg_dat_re  (simpleuart_reg_dat_sel && !mem_wstrb),
		.reg_dat_di  (mem_wdata),
		.reg_dat_do  (simpleuart_reg_dat_do),
		.reg_dat_wait(simpleuart_reg_dat_wait)
	);






	wire        lcd_rd;
	wire        lcd_newline;
	wire        lcd_newframe;
	wire [15:0] lcd_x;
	wire [15:0] lcd_y;
	reg  [4:0]  lcd_red;
	reg  [5:0]  lcd_grn;
	reg  [4:0]  lcd_blu;

	assign LCD_CLK = clk9M;

	LCDC _LCDC
	(
		.rst	   (resetn),
		.pclk	   (clk9M),

		.i_red     (lcd_red),	      // Red green and blue colour values
		.i_grn     (lcd_grn),	      // for each pixel
		.i_blu     (lcd_blu),
		.o_rd      (lcd_rd),		  // True when we can accept pixel data
		.o_newline (lcd_newline),	  // True on last pixel of each line
		.o_newframe(lcd_newframe),    // True on last pixel of each frame
		.o_x       (lcd_x),
		.o_y       (lcd_y),

		.LCD_DE	   (LCD_DEN),
		.LCD_HSYNC (LCD_HYNC),
		.LCD_VSYNC (LCD_SYNC),

		.LCD_B	   (LCD_B),
		.LCD_G	   (LCD_G),
		.LCD_R	   (LCD_R)
	);


	// assign  lcd_red =   (lcd_x <= 80) ? 5'd16 : 
	// 					(lcd_x <  160)? 5'd31 :  5'd0;

	// assign  lcd_grn =   ((lcd_x >= 160) && (lcd_x <= 240)) ? 6'd32 : 
	// 					((lcd_x >  240) && (lcd_x <= 320)) ? 6'd63 : 6'd0;

	// assign  lcd_blu =   ((lcd_x >  320) && (lcd_x <= 400)) ? 5'd16 : 
	// 					((lcd_x >  400) && (lcd_x <= 480)) ? 5'd31 : 5'd0;






endmodule









// Implementation note:
// Replace the following two modules with wrappers for your SRAM cells.

module picosoc_regs (
	input clk, wen,
	input [5:0] waddr,
	input [5:0] raddr1,
	input [5:0] raddr2,
	input [31:0] wdata,
	output [31:0] rdata1,
	output [31:0] rdata2
);
	reg [31:0] regs [0:31];

	always @(posedge clk)
		if (wen) regs[waddr[4:0]] <= wdata;

	assign rdata1 = regs[raddr1[4:0]];
	assign rdata2 = regs[raddr2[4:0]];
endmodule



