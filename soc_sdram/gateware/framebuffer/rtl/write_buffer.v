/*
 * write_buffer.v
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

module write_buffer #(
    parameter integer DATA = 36;
    parameter integer ADDR = 9;

	// auto
    parameter integer DL = DATA - 1;
    parameter integer AL = ADDR - 1;
)(
    // picorv32 interface - this is the write side
    input  wire        mem_valid_i,     // The picorv32 core initiates a memory transfer by asserting mem_valid
	input  wire        mem_instr_i,     // If the memory transfer is an instruction fetch, the picorv32 core asserts mem_instr
	output reg         mem_ready_o,     // The valid signal from picorv32 stays high until the peer asserts mem_ready

	input  wire [31:0] mem_addr_i,		// 
	input  wire [31:0] mem_wdata_i,		// In a read transfer mem_wdata is unused. The memory write the data at mem_wdata to the address mem_addr and acknowledges the transfer by asserting mem_ready.
	input  wire [3:0]  mem_wstrb_i,		// In a read transfer mem_wstrb has the value 0. In a write transfer mem_wstrb is not 0.
	output wire [31:0] mem_rdata_o,		// The memory reads the address mem_addr and makes the read value available on mem_rdata in the cycle mem_ready is high.

    // SDRAM burst interface - this is the burst read side
    input  wire [AL:0] sdram_col_addr_i,
    output reg  [31:0] sdram_dat_o,
    output reg  [10:0] sdram_row_addr_o,
    output reg         sdram_start_burst_o,
    input  wire        sdram_burst_done_i,


	// Common
	input  wire picorv32_clk,
	input  wire sdram_clk,
	input  wire rst
);

    // Signals for dual port ram
    wire                a_wr;
    wire    [AL:0]      a_addr;
    wire    [DL:0]      a_din;

    wire    [AL:0]      b_addr;
    reg     [DL:0]      b_dout;

    // Register for line address
    reg     [10:0]      line_address;
    wire                la_we;

    // Flush buffer to SDRAM command
    wire                flush_buf;

    // Dual port RAM - buffer that stores data that will be written to the framebuffer in the SDRAM
    dpram ram(
        // Port A: Write Port
        .a_clk(picorv32_clk),
        .a_wr(a_wr),
        .a_addr(a_addr),
        .a_din(a_din),

        // Port B: Read Port
        .b_clk(sdram_clk),
        .b_addr(b_addr),
        .b_dout(b_dout)
    );


    // Interface PicoRV32 native memory interface - write to buffer side
    assign a_wr   = ( (|mem_wstrb_i) && (mem_valid_i) && (mem_addr_i[31:16] == 8'h0300) ) ? 1'b1 : 1'b0;
    assign a_addr = mem_addr_i[AL:0];
    assign a_din  = mem_wdata_i;

    always @(posedge picorv32_clk) begin
        if (~mem_ready_o & (a_wr | la_wr) )
            mem_ready_o <= 1'b1;
        else
            mem_ready_o <= 1'b0;
    end

    // Interface PicoRV32 native memory interface - write to line address register
    assign la_wr   = ( (|mem_wstrb_i) && (mem_valid_i) && (mem_addr_i[31:16] == 8'h0301) ) ? 1'b1 : 1'b0;
    always @(posedge picorv32_clk) begin
        if ( la_wr )
            line_address <= mem_wdata_i;
    end


    // Interface to SDRAM burst controller - read from buffer side
    assign flush_buf   = ( (|mem_wstrb_i) && (mem_valid_i) && (mem_addr_i[31:16] == 8'h0302) ) ? 1'b1 : 1'b0;
    assign b_addr      = sdram_col_addr_i;
    assign sdram_dat_o = b_dout[31:0];

endmodule
