// TO DO:
// =====
//
// [] Change interfce to module
// [] Add image load functionality
//

`default_nettype none

module LCDC
(
    input  rst,
    input  pclk,

    input  wire [4:0]  i_red,	      // Red green and blue colour values
    input  wire [5:0]  i_grn,	      // for each pixel
    input  wire [4:0]  i_blu,
    output wire        o_rd,          // True when we can accept pixel data
    output wire        o_newline,	  // True on last pixel of each line
    output wire        o_newframe,    // True on last pixel of each frame
    output reg  [15:0] o_x,
    output reg  [15:0] o_y,

    output LCD_DE,
    output LCD_HSYNC,
    output LCD_VSYNC,

    output [4:0] LCD_B,
    output [5:0] LCD_G,
    output [4:0] LCD_R
);

    reg [15:0] x;
    reg [15:0] y;

    localparam vbp    = 16'd12; 
    localparam vpulse = 16'd4; 
    localparam vact   = 16'd272;
    localparam vfp    = 16'd8; 
    
    localparam hbp    = 16'd43; 
    localparam hpulse = 16'd4; 
    localparam hact   = 16'd480;
    localparam hfp    = 16'd8;    

    localparam xmax = hact + hbp + hfp;  	
    localparam ymax = vact + vbp + vfp;

    localparam xeol = hact + hbp + hpulse - 1;  	
    localparam yeof = vact + vbp + vpulse - 1;

    initial begin
        o_x <= 16'd0;
        o_y <= 16'd0;
    end

    always @( posedge pclk or negedge rst )begin
        if( !rst ) begin
            y <= 16'b0;    
            x <= 16'b0;
            end
        else if( x == xmax ) begin
            x <= 16'b0;
            y <= y + 1'b1;
            end
        else if( y == ymax ) begin
            y <=  16'b0;
            x <=  16'b0;
            end
        else
            x <= x + 1'b1;
    end

    assign o_newline  =  (x==xeol)               ? 1'b1 : 1'b0;
    assign o_newframe = ((x==xeol) && (y==yeof)) ? 1'b1 : 1'b0;

    always @( posedge pclk or negedge rst )begin
        if( !rst ) begin
            o_x <= 16'd0;    
            o_y <= 16'd0;
        end
        else begin
            if( o_rd ) 
                o_x <= o_x + 16'd1;    
            else 
                o_x <= 16'd0;

            if ( o_newframe ) 
                o_y <= 16'd0;
            else if ( o_newline && o_rd )
                o_y <= o_y + 16'd1;
        end
    end

    assign  LCD_HSYNC = (( x >= hpulse )&&( x <= (xmax-hfp))) ? 1'b0 : 1'b1;
    assign  LCD_VSYNC = (( y >= vpulse )&&( y <= (ymax-0) ))  ? 1'b0 : 1'b1;

    assign  LCD_DE = (  ( x >= hbp )&&
                        ( x <= xmax-hfp ) &&
                        ( y >= vbp ) &&
                        ( y <= ymax-vfp-1 ))  ? 1'b1 : 1'b0;

    assign o_rd =  ((x >= (hbp + hpulse)) && (x <= (hbp + hpulse + hact - 1))) 
                && ((y >= (vbp + 0)) && (y <= (vbp + 0 + vact - 1)));

    assign  LCD_R =  i_red;
    assign  LCD_G =  i_grn;
    assign  LCD_B =  i_blu;

    // assign  LCD_R =  x<= (hbp + hpulse +  80)? 5'd16 : 
    //                 (x<  (hbp + hpulse + 160)? 5'd31 :  5'd0);

    // assign  LCD_G =  (x>= (hbp + hpulse +  160) && x<= (hbp + hpulse +  240))? 6'd32 : 
    //                 ((x>  (hbp + hpulse +  240) && x<= (hbp + hpulse +  320))? 6'd63 : 6'd0);

    // assign  LCD_B =  (x>  (hbp + hpulse +  320) && x<= (hbp + hpulse +  400))? 5'd16 : 
    //                 ((x>  (hbp + hpulse +  400) && x<= (hbp + hpulse +  480))? 5'd31 : 6'd0);
                        

    /*
    assign  LCD_R   =   (x< (hbp + hpulse +  80))? 5'd0 : 
                        (x< (hbp + hpulse + 160)? 5'd6 :    
                        (x< (hbp + hpulse + 240)? 5'd12 :    
                        (x< (hbp + hpulse + 320)? 5'd18 :    
                        (x< (hbp + hpulse + 400)? 5'd24 :    
                        (x< (hbp + hpulse + 480)? 5'd31 :  5'd0 )))));
    assign  LCD_G = 6'b000000;
    assign  LCD_B = 5'b00000;
    */

endmodule
