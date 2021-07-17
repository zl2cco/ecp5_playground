`timescale 1 ns / 1 ps

module dpram_tb;
	reg         clk  = 1'b1;
    reg         a_wr = 1'b0;
    reg  [8:0]  a_addr;
    reg  [35:0] a_din;
    reg  [8:0]  b_addr;
    wire [35:0] b_dout;

    integer i;

	always #5 clk = ~clk;

    dpram dut (
        .a_clk(clk),
        .a_wr(a_wr),
        .a_addr(a_addr),
        .a_din(a_din),
        .b_clk(clk),
        .b_addr(b_addr),
        .b_dout(b_dout)
    );


	initial begin
		if ($test$plusargs("vcd")) begin
			$dumpfile("dpram_tb.vcd");
			$dumpvars(0, dpram_tb);
		end

//        #5 rst = 1;

        $display("Load DPRAM");
        for (i=0; i<480; i=i+1) begin
            @(posedge clk) begin
                a_addr <= i[8:0];
                a_din  <= {4'd0, i[31:0]};
                a_wr   <= 1'b1;
            end
            @(posedge clk) a_wr   = 1'b0;
        end

        $display("Check DPRAM");
        for (i=0; i<480; i=i+1) begin
            @(posedge clk) begin
                b_addr <= i[8:0];
            end
            @(posedge clk) begin
                if (b_dout != {4'd0, i[31:0]}) $display("Error at time %2d: %d", $time, i);
            end
        end
// $display("Time %2d: r_Data at Index %1d is %2d", $time, ii, r_Data[ii]);
// $display("Time %2d: r_Data at Index %1d is %2d", $time, ii, r_Data[ii]);

		repeat (10000) @(posedge clk);
		$finish;
	end
endmodule