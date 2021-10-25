/*
 * sdram_burst.v
 *
 * vim: ts=4 sw=4
 *
 * Copyright (C) 2020  Chris Conradie <zl2cco@gmail.com>
 * All rights reserved.
 *
 * BSD 3-clause, see LICENSE.bsd
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the <organization> nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

`default_nettype none

module sdram_burst #(
	parameter integer ADDR_WIDTH = 21,	/* Word address, 2 Mwords, [20:19] - bank address, [18:8] - row address, [7:0] - column address */
	parameter integer DATA_WIDTH = 32,
	parameter integer BLEN_WIDTH = 8,	// Burst length (number of words, 32-bits) to read or write
	parameter integer CMD_WIDTH  = 2,   // Commands are 0 - do nothing, 
										//				1 - burst read 240 (480 16-bits half words) columns from row address, 
										//				2 - burst write 240 (480 16-bits half words) columns to row address

	// auto
	parameter integer AL = ADDR_WIDTH - 1,
	parameter integer DL = DATA_WIDTH - 1,
	parameter integer BL = BLEN_WIDTH - 1,
	parameter integer CL = CMD_WIDTH  - 1
)(
	// Buffer interface - to load line buffer for display; to update row in frame buffer (SDRAM memory block) from the write buffer
	input  wire [CL:0] cmd_i,

	input  wire [AL:0] adr_i,			// Word address, 2 Mwords, [20:19] - bank address, [18:8] - row address, [7:0] - column address
	input  wire [BL:0] len_i,			// Number of words to load during burst
	input  wire [DL:0] dat_i,
	output wire [DL:0] dat_o,

	output wire        idle_o,			// Indicates SDRAM controller is in idle state when 1'b1
	output wire        valid_o,			// Indicates data is valid on dat_o; or dat_i. valid_o goes 1'b1 when first dat_i data is read (or first dat_o data is available)
										// and stays valid until len_i words have been processed
	output wire 	   burst_we_o,

	// SDRAM signals
	input  wire [DL:0] sdram_dq_i,
	output wire [DL:0] sdram_dq_o,
	output wire [10:0] sdram_addr,
	output wire [1:0]  sdram_ba,

	output wire        sdram_we_n,
	output wire        sdram_cas_n,
	output wire        sdram_ras_n,
	output wire        sdram_clk,

	// Common
	input  wire clk,
	input  wire rst
);

	// Constants
	// ---------
	localparam integer COUNTER_WIDTH = 22;
	localparam integer CW = COUNTER_WIDTH - 1;


`ifdef SIM
	localparam [CW:0]  CC_STARTUP_DELAY = 22'd5;
	localparam [CW:0]  REFRESH_PERIOD_CYCLES = 22'd8000;
`else
	localparam [CW:0]  CC_STARTUP_DELAY = 22'd40000;			// wait for a minimum of 200us, make this 400us
	localparam [CW:0]  REFRESH_PERIOD_CYCLES = 22'd8000; 		// tREF(max)=32ms, we used 16ms
`endif

	localparam [10:0] MODE_ADDR = 11'b00000110111;	// 00000 011 0 111
													//        |  |  |
													//        |  |  BURST LENGTH = FULL PAGE
													//		  |  WRAP TYPE = Sequential
													//        LATENCY = 3
	localparam		  MODE_BA = 2'b00;


	localparam [7:0]
		ST_START = 0,
		ST_START_WAIT_STARTUP = 1,
		ST_START_ISSUE_PRE_CHARGE = 2,
		ST_START_WAIT_PRE_CHARGE = 3,
		ST_START_ISSUE_AUTO_REFRESH = 4,
		ST_START_WAIT_AUTO_REFRESH = 5,
		ST_START_ISSUE_AUTO_REFRESH2 = 40,
		ST_START_WAIT_AUTO_REFRESH2 = 41,
		ST_START_ISSUE_SET_MODE_REG = 6,
		ST_START_WAIT_SET_MODE_REG = 7,

		ST_IDLE = 8,

		// burst write 240 (480 16-bits half words) columns to row address
		ST_WRITE_ISSUE_OPEN_ROW=9,					// Activate command		
		ST_WRITE_WAIT_OPEN_ROW=10,					// Wait for tRCD(min)=18ns (2 clock cycles for 100MHz clock)
		ST_WRITE_ISSUE_WRITE=11,					// Write without Auto Precharge (A10=1'b0)
		ST_WRITE_WAIT_WRITE=12,						// Wait for len_i writes to complete; stop write burst when last data is written
		ST_WRITE_ISSUE_PRECHARGE=13,
		ST_WRITE_WAIT_PRECHARGE=14,
		ST_WRITE_TERM_BURST=15,
		ST_WRITE_RECOVERY=16,

		// burst read 240 (480 16-bits half words) columns from row address, 
		ST_READ_ISSUE_OPEN_ROW=20,
		ST_READ_WAIT_OPEN_ROW=21,
		ST_READ_ISSUE_READ=22,
		ST_READ_WAIT_READ=23,
		ST_READ_LATCH_DATA=24,

		ST_ISSUE_PRECHARGE=25,
		ST_WAIT_PRECHARGE=26,
		ST_WAIT_EOSTB=27,

		ST_ISSUE_AUTO_REFRESH=30,
		ST_WAIT_AUTO_REFRESH=31;



	// Signals
	// -------

	// Control
	reg  [7:0]  ctrl_state;
	reg  [7:0]  ctrl_state_nxt;

	reg  [DL:0] rdata, rdata_nxt;
//	reg  [DL:0] wdata, wdata_nxt;
	reg  [AL:0] address, address_nxt;

	reg  [BL:0] len, len_nxt;

	wire [7:0]  ca;
	wire [10:0] ra;
	wire        a10;
	wire [1:0]  ba;

	wire 		cmd_nop;
	wire        cmd_auto_refresh;
	wire        cmd_open_row;
	wire        cmd_read;
	wire        cmd_write;
	wire        cmd_precharge;
	wire        cmd_precharge_both;
	wire 		cmd_set_mode_reg;
	wire        cmd_term_burst;

	// Status
	wire        status_burst_write;

	// Counter
	reg  [CW:0] counter;
	reg  [CW:0] refresh_counter;
	reg         counter_rst;

	reg         refresh, refresh_nxt;

	// Control
	// -------

	// Counter register
	always @(posedge clk) 
		if (counter_rst) 
			counter <= 0;
		else
			counter <= counter + 1;


	// Refresh Counter register
	always @(posedge clk) 
		if (rst) begin
			refresh_counter <= 0;
			refresh <= 0;
		end
		else if (refresh_counter == REFRESH_PERIOD_CYCLES) begin
			refresh_counter <= 0;
			refresh <= 1;		
		end
		else begin
			refresh_counter <= refresh_counter + 1;
			refresh <= refresh_nxt;		
		end

	// FSM state register
	always @(posedge clk or posedge rst)
		if (rst) 
			ctrl_state <= ST_START;
		else
			ctrl_state <= ctrl_state_nxt;

	// Address and data register
	always @(posedge clk or posedge rst)
		if (rst) begin
			address <= 21'd0;
			rdata   <= 32'd0;
//			wdata   <= 32'd0;
			len     <=  8'd0;
		end
		else begin
			address <= address_nxt;
			rdata   <= rdata_nxt;			
//			wdata   <= wdata_nxt;			
			len     <= len_nxt;
		end

	// FSM next-state logic
	always @(*)
	begin
		// Default is not to move
		ctrl_state_nxt = ctrl_state;
		address_nxt    = address;
		rdata_nxt      = rdata;
//		wdata_nxt      = wdata;
		counter_rst    = 0;
		refresh_nxt    = refresh;
		len_nxt        = len;

		// State change logic
		case (ctrl_state)

			// Startup
			//--------
			ST_START: begin
				ctrl_state_nxt = ST_START_WAIT_STARTUP;
				counter_rst = 1;
			end
			ST_START_WAIT_STARTUP:
				if (counter == (CC_STARTUP_DELAY-1)) begin
					counter_rst = 1;
					ctrl_state_nxt = ST_START_ISSUE_PRE_CHARGE;
				end
			ST_START_ISSUE_PRE_CHARGE:
				ctrl_state_nxt = ST_START_WAIT_PRE_CHARGE;

			ST_START_WAIT_PRE_CHARGE:
				if (counter == 2) begin
					counter_rst = 1;
					ctrl_state_nxt = ST_START_ISSUE_AUTO_REFRESH;
				end
			ST_START_ISSUE_AUTO_REFRESH:
				ctrl_state_nxt = ST_START_WAIT_AUTO_REFRESH;
			ST_START_WAIT_AUTO_REFRESH:
				if (counter == (7-1)) begin
					counter_rst = 1;
					ctrl_state_nxt = ST_START_ISSUE_AUTO_REFRESH2;
				end
			ST_START_ISSUE_AUTO_REFRESH2:
				ctrl_state_nxt = ST_START_WAIT_AUTO_REFRESH2;
			ST_START_WAIT_AUTO_REFRESH2:
				if (counter == (7-1)) begin
					counter_rst = 1;
					ctrl_state_nxt = ST_START_ISSUE_SET_MODE_REG;
				end
			ST_START_ISSUE_SET_MODE_REG:
				ctrl_state_nxt = ST_IDLE;
			ST_START_WAIT_SET_MODE_REG:     // TODO: REMOVE
				ctrl_state_nxt = ST_IDLE;


			// IDLE, WAIT FOR NEXT BUS CYCLE
			//------------------------------
			ST_IDLE: begin
				counter_rst = 1'd1;
				address_nxt = adr_i;
//				wdata_nxt   = dat_i;
				len_nxt     = len_i;

				case (cmd_i)
					2'd1: begin										// burst read 240 (480 16-bits half words) columns from row address, 
						ctrl_state_nxt = ST_READ_ISSUE_OPEN_ROW;
					end
					2'd2: begin										// burst write 240 (480 16-bits half words) columns to row address
						ctrl_state_nxt = ST_WRITE_ISSUE_OPEN_ROW;
					end
					default: begin
						if (refresh) begin
							counter_rst = 1;
							refresh_nxt = 0;
							ctrl_state_nxt = ST_ISSUE_AUTO_REFRESH;
						end
					end
				endcase
			end

				//TODO: AUTO REFRESH process

			// WRITE
			//------
			ST_WRITE_ISSUE_OPEN_ROW: begin
				ctrl_state_nxt = ST_WRITE_WAIT_OPEN_ROW;
				counter_rst = 1'd1;
			end
			ST_WRITE_WAIT_OPEN_ROW:
				if (counter == 1) begin
					counter_rst = 1'd1;
//					wdata_nxt   = dat_i;
					ctrl_state_nxt = ST_WRITE_ISSUE_WRITE;
				end
			ST_WRITE_ISSUE_WRITE: begin
				ctrl_state_nxt = ST_WRITE_WAIT_WRITE;
//				wdata_nxt   = dat_i;
				len_nxt        = len - 1;
			end
			ST_WRITE_WAIT_WRITE: begin
				counter_rst    = 1'd1;
//				wdata_nxt   = dat_i;
				len_nxt        = len - 1;
				if (len == 1)
					ctrl_state_nxt = ST_WRITE_TERM_BURST;				
			end
			ST_WRITE_TERM_BURST: begin
				counter_rst    = 1'd1;
				ctrl_state_nxt = ST_WRITE_RECOVERY;				
			end
			ST_WRITE_RECOVERY: begin
				if (counter == 1) begin
					counter_rst = 1;
					ctrl_state_nxt = ST_ISSUE_PRECHARGE;
				end
			end

			// READ
			//-----
			ST_READ_ISSUE_OPEN_ROW: begin
				ctrl_state_nxt = ST_READ_WAIT_OPEN_ROW;
				counter_rst = 1;
			end
			ST_READ_WAIT_OPEN_ROW:
//				if (counter == 4) begin
				if (counter == 1) begin
					counter_rst = 1;
					ctrl_state_nxt = ST_READ_ISSUE_READ;
				end
			ST_READ_ISSUE_READ:
				ctrl_state_nxt = ST_READ_WAIT_READ;
			ST_READ_WAIT_READ:
				if (counter == 2) begin 
					counter_rst = 1;
					ctrl_state_nxt = ST_READ_LATCH_DATA;
				end
			ST_READ_LATCH_DATA: begin
				rdata_nxt   = sdram_dq_i;
				counter_rst = 1'd1;	
				len_nxt     = len - 1;
				if (len == 1)
					ctrl_state_nxt = ST_ISSUE_PRECHARGE;				
			end

			// PRECHARGE
			//==========
			ST_ISSUE_PRECHARGE:
				ctrl_state_nxt = ST_WAIT_PRECHARGE;
			ST_WAIT_PRECHARGE:
				if (counter == 4) begin
					counter_rst = 1;
					ctrl_state_nxt = ST_IDLE;
				end

			// AUTO REFRESH
			//-------------
			ST_ISSUE_AUTO_REFRESH:
				ctrl_state_nxt = ST_WAIT_AUTO_REFRESH;
			ST_WAIT_AUTO_REFRESH:
				if (counter == 6) begin
					counter_rst = 1;
					ctrl_state_nxt = ST_IDLE;
				end
		endcase
	end


//====================================================================
//FIXME: 
//	FIXED 1. RAS|CAS|WE low means mode reg, change to NOP when waiting
//====================================================================

	// State conditions
	// assign ctrl_bus_mode = ctrl_state == ST_BUS_MODE;
	assign cmd_nop           =   (ctrl_state == ST_START)
	                           ||(ctrl_state == ST_START_WAIT_STARTUP)
	                           ||(ctrl_state == ST_START_WAIT_PRE_CHARGE)
	                           ||(ctrl_state == ST_START_WAIT_AUTO_REFRESH)
	                           ||(ctrl_state == ST_START_WAIT_AUTO_REFRESH2)
	                           ||(ctrl_state == ST_START_WAIT_SET_MODE_REG)

	                           ||(ctrl_state == ST_IDLE)

	                           ||(ctrl_state == ST_READ_WAIT_OPEN_ROW)
	                           ||(ctrl_state == ST_READ_WAIT_READ)
	                           ||( (ctrl_state == ST_READ_LATCH_DATA) && (len != 3) )
	                           ||(ctrl_state == ST_WAIT_PRECHARGE)
	                           ||(ctrl_state == ST_WAIT_EOSTB)

	                           ||(ctrl_state == ST_WRITE_WAIT_OPEN_ROW)
	                           ||(ctrl_state == ST_WRITE_WAIT_WRITE)
	                           ||(ctrl_state == ST_WRITE_RECOVERY)
	                           ||(ctrl_state == ST_WAIT_PRECHARGE)
	                           ||(ctrl_state == ST_WAIT_EOSTB)

	                           ||(ctrl_state == ST_WAIT_AUTO_REFRESH);
	
	assign cmd_auto_refresh  =   (ctrl_state == ST_START_ISSUE_AUTO_REFRESH)
	                           ||(ctrl_state == ST_START_ISSUE_AUTO_REFRESH2)
	                           ||(ctrl_state == ST_ISSUE_AUTO_REFRESH);
	
	assign cmd_open_row      =   (ctrl_state == ST_WRITE_ISSUE_OPEN_ROW)
	                           ||(ctrl_state == ST_READ_ISSUE_OPEN_ROW);
	
	assign cmd_read          =   (ctrl_state == ST_READ_ISSUE_READ);
	
	assign cmd_write         =   (ctrl_state == ST_WRITE_ISSUE_WRITE);

	assign cmd_precharge     =   (ctrl_state == ST_START_ISSUE_PRE_CHARGE)
	                           ||(ctrl_state == ST_ISSUE_PRECHARGE)
	                           ||(ctrl_state == ST_ISSUE_PRECHARGE);

	assign cmd_precharge_both=   (ctrl_state == ST_START_ISSUE_PRE_CHARGE);

	assign cmd_set_mode_reg  =   (ctrl_state == ST_START_ISSUE_SET_MODE_REG);

	assign cmd_term_burst    =   (ctrl_state == ST_WRITE_TERM_BURST)
							   ||( (ctrl_state == ST_READ_LATCH_DATA) && (len == 3) );


	assign status_burst_write= ((ctrl_state == ST_WRITE_ISSUE_WRITE) || (ctrl_state == ST_WRITE_WAIT_WRITE)) ? 1 : 0;
	assign burst_we_o        = status_burst_write;
	assign idle_o            =  (ctrl_state == ST_IDLE) ? 1 : 0;
	assign valid_o           = ((ctrl_state == ST_WRITE_ISSUE_WRITE) || (ctrl_state == ST_WRITE_WAIT_WRITE)) ? 1 : 
							   ((ctrl_state == ST_READ_LATCH_DATA)) ? 1 : 0;

	// Memory interface
	// ----------------

	// Issue commands

	assign sdram_we_n  = (cmd_nop || cmd_auto_refresh || cmd_open_row || cmd_read) 
							? 1 : 0;

	assign sdram_cas_n = (cmd_nop || cmd_open_row || cmd_precharge || cmd_precharge_both || cmd_term_burst) 
							? 1 : 0;

	assign sdram_ras_n = (cmd_nop || cmd_read || cmd_write || cmd_term_burst) 
							? 1 : 0;


	// Clock

	assign sdram_clk   = ~clk;


	// Set address and data lines, capture data

	assign sdram_dq_o  = dat_i;
//	assign sdram_dq_o  = wdata;

	assign sdram_addr  = (cmd_open_row)          ? ra 
	                    :(cmd_read || cmd_write) ? (ca | 11'b00000000000)  
	                    :(cmd_precharge_both)    ? 11'b10000000000 
	                    :(cmd_set_mode_reg)      ? MODE_ADDR
	                    : 0 ;

	assign sdram_ba    = (cmd_open_row || cmd_read || cmd_write || cmd_precharge) ? ba 
	                    :(cmd_set_mode_reg) ? MODE_BA
	                    : 0;


	// Decode address

	assign ca = address[7:0];
	assign ra = address[18:8];
	assign ba = address[20:19];
	assign a10= sdram_addr[10];




	// Misc interface
	// ----------------

//	assign dat_o       = rdata;
	assign dat_o       = sdram_dq_i;

endmodule
