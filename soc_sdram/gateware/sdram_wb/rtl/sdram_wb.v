/*
 * sdram_wb.v
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

module sdram_wb #(
	parameter integer ADDR_WIDTH = 21,	/* Word address, 1 Mbytes */
	parameter integer DATA_WIDTH = 32,

	// auto
	parameter integer AL = ADDR_WIDTH - 1,
	parameter integer DL = DATA_WIDTH - 1
)(
	// Wishbone Interface
	input  wire [AL:0] adr_i,
	input  wire [DL:0] dat_i,
	input  wire        cyc_i,
	input  wire        stb_i,
	input  wire        we_i,

	output wire [DL:0] dat_o,
	output wire        ack_o,

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
	localparam [CW:0]  REFRESH_PERIOD_CYCLES = 22'd100;
`else
	localparam [CW:0]  CC_STARTUP_DELAY = 22'd40000;			// wait for a minimum of 200us, make this 400us
	localparam [CW:0]  REFRESH_PERIOD_CYCLES = 22'd8000; 		// tREF(max)=32ms, we used 16ms
`endif

	localparam [10:0] MODE_ADDR = 11'b00000110000;	// 00000 011 0 000
													//        |  |  |
													//        |  |  BURST LENGTH = 1
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

		ST_WRITE_ISSUE_OPEN_ROW=9,
		ST_WRITE_WAIT_OPEN_ROW=10,
		ST_WRITE_ISSUE_WRITE=11,
		ST_WRITE_WAIT_WRITE=12,
		ST_WRITE_ISSUE_PRECHARGE=13,
		ST_WRITE_WAIT_PRECHARGE=14,
		ST_WRITE_WAIT_EOSTB=15,

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
	reg  [DL:0] wdata, wdata_nxt;
	reg  [AL:0] address, address_nxt;

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
			address <= 20'd0;
			rdata   <= 32'd0;
			wdata   <= 32'd0;
		end
		else begin
			address <= address_nxt;
			rdata   <= rdata_nxt;			
			wdata   <= wdata_nxt;			
		end

	// FSM next-state logic
	always @(*)
	begin
		// Default is not to move
		ctrl_state_nxt = ctrl_state;
		address_nxt    = address;
		rdata_nxt      = rdata;
		wdata_nxt      = wdata;
		counter_rst    = 0;
		refresh_nxt    = refresh;

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
				if (cyc_i && stb_i) begin
					counter_rst = 1;
					address_nxt = adr_i;
					wdata_nxt   = dat_i;

					if (we_i)
						ctrl_state_nxt = ST_WRITE_ISSUE_OPEN_ROW;
					else 
						ctrl_state_nxt = ST_READ_ISSUE_OPEN_ROW;
				end

				if (refresh) begin
					counter_rst = 1;
					refresh_nxt = 0;
					ctrl_state_nxt = ST_ISSUE_AUTO_REFRESH;
				end
			end

				//TODO: AUTO REFRESH process

			// WRITE
			//------
			ST_WRITE_ISSUE_OPEN_ROW: begin
				ctrl_state_nxt = ST_WRITE_WAIT_OPEN_ROW;
				counter_rst = 1;
			end
			ST_WRITE_WAIT_OPEN_ROW:
				if (counter == 1) begin
					counter_rst = 1;
					ctrl_state_nxt = ST_WRITE_ISSUE_WRITE;
				end
			ST_WRITE_ISSUE_WRITE: begin
				ctrl_state_nxt = ST_WRITE_WAIT_WRITE;
			end
			ST_WRITE_WAIT_WRITE: begin
				counter_rst = 1;
//				ctrl_state_nxt = ST_ISSUE_PRECHARGE;				
				ctrl_state_nxt = ST_WAIT_EOSTB;
			end

			// READ
			//-----
			ST_READ_ISSUE_OPEN_ROW: begin
				ctrl_state_nxt = ST_READ_WAIT_OPEN_ROW;
				counter_rst = 1;
			end
			ST_READ_WAIT_OPEN_ROW:
				if (counter == 4) begin
//				if (counter == 1) begin
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
//				ctrl_state_nxt = ST_ISSUE_PRECHARGE;
				ctrl_state_nxt = ST_WAIT_EOSTB;
				`ifdef SIM
					rdata_nxt = 32'haabbccdd; // sdram_dq_i;
				`else
					rdata_nxt = sdram_dq_i;
				`endif				
				counter_rst = 1;
			end


			// PRECHARGE
			//==========
			ST_ISSUE_PRECHARGE:
				ctrl_state_nxt = ST_WAIT_PRECHARGE;
			ST_WAIT_PRECHARGE:
				if (counter == 1) begin
					counter_rst = 1;
					ctrl_state_nxt = ST_WAIT_EOSTB;
				end
			ST_WAIT_EOSTB:
				if (~stb_i) begin
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
	                           ||(ctrl_state == ST_READ_LATCH_DATA)
	                           ||(ctrl_state == ST_WAIT_PRECHARGE)
	                           ||(ctrl_state == ST_WAIT_EOSTB)

	                           ||(ctrl_state == ST_WRITE_WAIT_OPEN_ROW)
	                           ||(ctrl_state == ST_WRITE_WAIT_WRITE)
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

	// Memory interface
	// ----------------

	// Issue commands

	assign sdram_we_n  = (cmd_nop || cmd_auto_refresh || cmd_open_row || cmd_read) 
							? 1 : 0;

	assign sdram_cas_n = (cmd_nop || cmd_open_row || cmd_precharge || cmd_precharge_both) 
							? 1 : 0;

	assign sdram_ras_n = (cmd_nop || cmd_read || cmd_write) 
							? 1 : 0;


	// Clock

	assign sdram_clk   = ~clk;


	// Set address and data lines, capture data

	assign sdram_dq_o  = wdata;

	assign sdram_addr  = (cmd_open_row)          ? ra 
	                    :(cmd_read || cmd_write) ? (ca | 11'b10000000000)  
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




	// Wishbone interface
	// ----------------

	// Wishbone acknowledge 
	assign ack_o       = (ctrl_state == ST_WAIT_EOSTB)  
	                   ||(ctrl_state == ST_READ_LATCH_DATA)
	                        ? 1 : 0;

//	assign dat_o       = rdata;
	assign dat_o       = sdram_dq_i;

endmodule
