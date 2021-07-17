`timescale 1 ns / 1 ps

module sdram_burst_write_tb;

    parameter integer ADDR_WIDTH = 21;	/* Word address, 2 Mwords, [20:19] - bank address, [18:8] - row address, [7:0] - column address */
    parameter integer DATA_WIDTH = 32;
    parameter integer BLEN_WIDTH = 8;	// Burst length (number of words, 32-bits) to read or write
    parameter integer CMD_WIDTH  = 2;   // Commands are 0 - do nothing, 
                                        //				1 - burst read 240 (480 16-bits half words) columns from row address, 
                                        //				2 - burst write 240 (480 16-bits half words) columns to row address
    parameter integer LINE_BUFFER_LEN = 480;

    // auto
    parameter integer AL = ADDR_WIDTH - 1;
    parameter integer DL = DATA_WIDTH - 1;
    parameter integer BL = BLEN_WIDTH - 1;
    parameter integer CL = CMD_WIDTH  - 1;
    parameter integer LL = LINE_BUFFER_LEN  - 1;




	reg         clk  = 1'b1;
	wire        sdram_clk  = 1'b1;
	reg         rst  = 1'b1;

	reg  [CL:0]  cmd_i;
	reg  [AL:0]  adr_i;			
	reg  [BL:0]  len_i;			
	wire [DL:0]  dat_i;
	wire [DL:0]  dat_o;
	wire         idle_o;			
	wire         valid_o;

	reg  [DL:0] sdram_dq_i, ii=0;

    reg  [DL:0]  line_buffer[0:LL];		

    integer i;

	always #5 clk = ~clk;
    assign sdram_clk = ~clk;

    always @(posedge clk) begin
        sdram_dq_i <= ii;
        ii <= ii + 1;
    end


    sdram_burst dut (
        .cmd_i(cmd_i),
        .adr_i(adr_i),			// Word address, 2 Mwords, [20:19] - bank address, [18:8] - row address, [7:0] - column address
        .len_i(len_i),			// Number of words to load during burst
        .dat_i(dat_i),
        .dat_o(dat_o),
        .idle_o(idle_o),			// Indicates SDRAM controller is in idle state when 1'b1
        .valid_o(valid_o),			// Indicates data is valid on dat_o; or dat_i. valid_o goes 1'b1 when first dat_i data is read (or first dat_o data is available)
        .sdram_dq_i(sdram_dq_i),
        .sdram_dq_o(),
        .sdram_addr(),
        .sdram_ba(),
        .sdram_we_n(),
        .sdram_cas_n(),
        .sdram_ras_n(),
        .sdram_clk(),
        .clk(clk),
        .rst(rst)
    );


	// Stimulus
	// --------

	task burst_cmd;
        input  [CL:0]  cmd;
    	input  [AL:0]  adr;	
		input  [BL:0]  len;
		begin
            $display("Time %2d: i %1d valid %2d addr %3d len %4d", $time, i, valid_o, adr, len);

            //Do not need to wait for idle state; setup command and then wait for valid to indicate when valid data is available.
            //if (idle_o == 0) @(posedge idle_o);

            // Check whether transaction is already underway
            if (valid_o == 1'b0) begin

                @(posedge clk) begin
                    cmd_i <= cmd;
                    adr_i <= adr;
                    len_i <= len;
                    i     <= 0;
                end

                @(posedge valid_o) 
                cmd_i <= 0;

                while ((valid_o == 1)&&(i<480)) 
                    @(posedge clk) begin
                        i <= i + 1;
    //                    $display("Time %2d: i %1d valid %2d", $time, i, valid_o);
                    end
                $display("Time %2d: received %1d words (32 bits)", $time, i);
    		end
            else begin
                $display("A transaction is still underway (valid_o is asserted)");
            end
        end
	endtask

    // Assign test data to the dat_i of the framebuffer
    assign dat_i = line_buffer[i];

	initial begin
		if ($test$plusargs("vcd")) begin
			$dumpfile("sdram_burst_write_tb.vcd");
			$dumpvars(0, sdram_burst_write_tb);
		end

        // Reset signal
        #5 rst = 1;
        #5 rst = 0;

        // Wait for framebuffer module to be in idle state
        // $display("Wait for IDLE state");
        // @(posedge idle_o); 

        // Load test data
        $display("Load line buffer");
        for (i=0; i<480; i=i+1) begin
            line_buffer[i] = i;
        end

        // Complete a burst write
        $display("Write line buffer to frame buffer");
        burst_cmd(2, 21'd1,8'd240);
        $display("Done");

        // Complete a burst write
        $display("Write line buffer to frame buffer");
        burst_cmd(2, 21'h00302, 8'd240);
        $display("Done");



        // Load test data
        $display("Load line buffer");
        for (i=0; i<480; i=i+1) begin
            line_buffer[i] = 479 - i;
        end

        // Complete a burst read
        $display("Write line buffer to frame buffer");
        burst_cmd(1, 21'h00403, 8'd240);
        $display("Done");

        // Complete a burst read
        $display("Write line buffer to frame buffer");
        burst_cmd(1, 21'h00705, 8'd240);
        $display("Done");

 // $display("Time %2d: r_Data at Index %1d is %2d", $time, ii, r_Data[ii]);
// $display("Time %2d: r_Data at Index %1d is %2d", $time, ii, r_Data[ii]);

		repeat (10000) @(posedge clk);
		$finish;
	end
endmodule