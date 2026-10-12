//Single cordic step block
    module cordic_step ( clock, ce, sin_in, cos_in, angle_in, t_angle, 
                         atan, sin_out, cos_out, angle_out, t_angle_out ); 
    parameter integer step = 0; //Step number
    parameter integer W = 16; //Fixed-point representation precision fixpoint(6:10)
    input clock, ce;
    input signed [W-1:0] sin_in, cos_in;
    input [W-1:0] angle_in, atan;
    input [W-1:0] t_angle;
    output reg signed [W-1:0] sin_out, cos_out; 
    output reg signed [W-1:0] angle_out; 
    output reg [W-1:0] t_angle_out;
    //
    always @ (posedge clock)
    begin
        if( ce == 1'b1 )
        begin    
            if(t_angle > angle_in)
            begin
               cos_out <= cos_in - (sin_in >>> step); //Arithmetic shift !!!
               sin_out <= (cos_in >>> step) + sin_in;
               angle_out <= angle_in + atan;
            end
            else
            begin
               cos_out <= cos_in + (sin_in >>> step);
               sin_out <= -(cos_in >>> step) + sin_in;
               angle_out <= angle_in - atan;
            end   
            t_angle_out <= t_angle;
        end //if ( ce == 1'b1 )
    end
    endmodule
    
    // Multiplication by constant Kn value
    module mul_Kn(clock, ce, value_in, value_out);
    parameter integer W = 16; //Fixed-point representation precision fixpoint(6:10)
    parameter FXP_SHIFT = 10;
    input clock, ce;
    input signed[W-1:0] value_in;
    output reg signed[W-1:0] value_out;
    //Shifted left values of input
    reg signed [2*W-1:0] val, val_0, val_2, val_4, val_5, val_7, val_7_9_d, val_9;
    //Accumulated shifted values
    reg signed [2*W-1:0] val_0_2, val_4_5, val_7_9, val_0_2_4_5, val_0_2_4_5_7_9;
    //
    always @ (posedge clock)
    begin
        if( ce == 1'b1 )
        begin
        //Pipe step 1
            val = value_in; val_0 <= val; val_2 <= val << 2; val_4 <= val << 4;
            val_5 <= val << 5; val_7 <= val << 7; val_9 <= val << 9;
        //Pipe step 2        
            val_0_2 <= val_0 - val_2; val_4_5 <= val_4 - val_5; val_7_9 <= val_7 + val_9;
        //Pipe step 3     
            val_0_2_4_5 <= val_0_2 + val_4_5;
            val_7_9_d <= val_7_9; //delay val_7_9 which is necessary in the 4-th pipe stage
        //Pipe step 4    
            val_0_2_4_5_7_9 = val_0_2_4_5 + val_7_9_d;
        //Pipe step 5 //Normalise    
            value_out <= val_0_2_4_5_7_9 >>> FXP_SHIFT;
        end
    end
    endmodule
    
    module cordic_pipelined( clock, reset, ce, angle_in, sin_out, cos_out, valid_out ); 
    parameter integer W = 16; //Fixed-point representation precision fixpoint(6:10)
    parameter FXP_MUL = 1024;
    parameter PIPE_LATENCY = 15;
    input clock, reset, ce;
    input /*signed*/ [W-1:0] angle_in;
    output /*signed*/ [W-1:0] sin_out, cos_out;
    output valid_out;   //Pipe output is valid d
    
    //Cordic look-up table
    reg /*signed*/ [W-1:0] atan[0:10];
    
    initial begin
        atan[0] = 12'b001100100100; 
        atan[1] = 12'b000111011011;
        atan[2] = 12'b000011111011;
        atan[3] = 12'b000001111111;
        atan[4] = 12'b000001000000;
        atan[5] = 12'b000000100000;
        atan[6] = 12'b000000010000;
        atan[7] = 12'b000000001000;
        atan[8] = 12'b000000000100;
        atan[9] = 12'b000000000010;  
        atan[10] = 12'b000000000001;                    
    end
    
    //Tabs of wires provide connections for cordic pipelined modules
    wire /*signd*/ [W-1:0] sin_tab [0:11]; 
    wire /*signed*/ [W-1:0] cos_tab [0:11];
    wire /*signed*/ [W-1:0] t_angle_tab [0:11];      //Target angle must be pipelined
    wire /*signed*/ [W-1:0] angle_tab [0:11];
    //
    reg [7:0] valid_cnt;                //It count pipeline delay
    
   //Synchronious activity
    always@(posedge clock)
    begin
        if ( reset == 1'b1 ) 
            valid_cnt <= PIPE_LATENCY;
        else
            if( ( valid_cnt != 0 ) && ( ce == 1'b1 ) ) valid_cnt <= valid_cnt - 1; //Valid output data moved toward output
    end
    //Set constant values
    assign cos_tab[0] = 1 * FXP_MUL;
    assign sin_tab[0] = 0;
    assign angle_tab[0] = 0;
    assign t_angle_tab[0] = angle_in;
    //Valid_out is true then the pipe is already full
    assign valid_out = ( valid_cnt == 0 )? 1'b1 : 1'b0;
    //Modules netlist
    //Cordic rotation pipeline
        cordic_step #(0) cordic_step_0 ( clock, ce, sin_tab[0], cos_tab[0], angle_tab[0], t_angle_tab[0], atan[0], 
                                        sin_tab[1], cos_tab[1], angle_tab[1], t_angle_tab[1] );
        cordic_step #(1) cordic_step_1 ( clock, ce, sin_tab[1], cos_tab[1], angle_tab[1], t_angle_tab[1], atan[1], 
                                        sin_tab[2], cos_tab[2], angle_tab[2], t_angle_tab[2] );
        cordic_step #(2) cordic_step_2 ( clock, ce, sin_tab[2], cos_tab[2], angle_tab[2], t_angle_tab[2], atan[2], 
                                        sin_tab[3], cos_tab[3], angle_tab[3], t_angle_tab[3] );
        cordic_step #(3) cordic_step_3 ( clock, ce, sin_tab[3], cos_tab[3], angle_tab[3], t_angle_tab[3], atan[3], 
                                        sin_tab[4], cos_tab[4], angle_tab[4], t_angle_tab[4] );
        cordic_step #(4) cordic_step_4 ( clock, ce, sin_tab[4], cos_tab[4], angle_tab[4], t_angle_tab[4], atan[4], 
                                        sin_tab[5], cos_tab[5], angle_tab[5], t_angle_tab[5] );
        cordic_step #(5) cordic_step_5 ( clock, ce, sin_tab[5], cos_tab[5], angle_tab[5], t_angle_tab[5], atan[5], 
                                        sin_tab[6], cos_tab[6], angle_tab[6], t_angle_tab[6] );
        cordic_step #(6) cordic_step_6 ( clock, ce, sin_tab[6], cos_tab[6], angle_tab[6], t_angle_tab[6], atan[6], 
                                        sin_tab[7], cos_tab[7], angle_tab[7], t_angle_tab[7] );
        cordic_step #(7) cordic_step_7 ( clock, ce, sin_tab[7], cos_tab[7], angle_tab[7], t_angle_tab[7], atan[7], 
                                        sin_tab[8], cos_tab[8], angle_tab[8], t_angle_tab[8] );
        cordic_step #(8) cordic_step_8 ( clock, ce, sin_tab[8], cos_tab[8], angle_tab[8], t_angle_tab[8], atan[8], 
                                        sin_tab[9], cos_tab[9], angle_tab[9], t_angle_tab[9] );
        cordic_step #(9) cordic_step_9 ( clock, ce, sin_tab[9], cos_tab[9], angle_tab[9], t_angle_tab[9], atan[9], 
                                        sin_tab[10], cos_tab[10], angle_tab[10], t_angle_tab[10] );
        cordic_step #(10)cordic_step_10( clock, ce, sin_tab[10], cos_tab[10], angle_tab[10], t_angle_tab[10], atan[10], 
                                        sin_tab[11], cos_tab[11], angle_tab[11], t_angle_tab[11] );
    //Results scaling
        mul_Kn mul_Kn_sin ( clock, ce, sin_tab[11], sin_out );
        mul_Kn mul_Kn_cos ( clock, ce, cos_tab[11], cos_out );
    
    endmodule