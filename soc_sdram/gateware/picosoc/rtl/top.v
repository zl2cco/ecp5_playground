`default_nettype none

module top(
    // Clock signals
    input clkin,
    output clkout,

    // LEDs
    output led,

    // UART signals
    output uart_tx,
    input uart_rx,

	// SDRAM signals
	input  wire [31:0] sdram_dq,
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
	output wire        [4:0] LCD_B

);

wire clk;
wire int_led;
wire clk100M, clk100M180, clk9, locked;
wire [31:0] sdram_dq_i, sdram_dq_o;
wire we;
//wire sdram_we_n, we;

// pll_12_50 pll(
//     .clki(clkin),
//     .clko(clk)
// );

pll pll
(
    .clk(clkin),             // 25 MHz, 0 deg
    .clk100M(clk100M),       // 100 MHz, 0 deg
    .clk100M180(clk100M180), // 100 MHz, 180 deg
    .clk50M(clk),            // 50 MHz, 0 deg
    .clk9(clk9),
    .locked(locked)
);


picosoc soc(
    .clk(clk),
    .led(int_led),
    .uart_tx(uart_tx),
    .uart_rx(uart_rx),


    .sdram_dq_i(sdram_dq_i),
    .sdram_dq_o(sdram_dq_o),
    .sdram_addr(sdram_addr),
    .sdram_ba(sdram_ba),
    .sdram_we_n(sdram_we_n),
    .sdram_cas_n(sdram_cas_n),
    .sdram_ras_n(sdram_ras_n),
    .sdram_clk(),

	.LCD_CLK(LCD_CLK),
	.LCD_HYNC(LCD_HYNC),
	.LCD_SYNC(LCD_SYNC),
	.LCD_DEN(LCD_DEN),
	.LCD_R(LCD_R),
	.LCD_G(LCD_G),
	.LCD_B(LCD_B),

    .clk100M(clk100M),
    .clk9M(clk9)
);

assign led = int_led;
assign clkout = clk9;

assign sdram_clk = clk100M180;

assign we = (~sdram_we_n) && sdram_ras_n && (~sdram_cas_n);

BB bb_inst[31:0] (
    .I(sdram_dq_o), 
    .T(we),  
    .O(sdram_dq_i), 
    .B(sdram_dq)
); 

endmodule
