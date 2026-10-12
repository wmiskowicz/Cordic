module cordic_rtl_tb;

// ----- Local parameters -----
parameter WIDTH = 16;
parameter FXP_SHIFT = 10;
parameter FXP_SCALE = 2**FXP_SHIFT;

localparam PERIODS_TO_GENERATE = 10;
localparam ANGLE_STEP = 100;
localparam PI = integer'(3.14 * FXP_SCALE);


// ----- Local variables -----
logic signed [WIDTH-1:0] cos_out;
logic signed [WIDTH-1:0] sin_out;

real angle_real;
reg signed [WIDTH-1:0] angle_signed;


logic clk;
logic reset;
logic start;
logic ready_out;


// ----- Clock -----
initial begin
  clk = 1'b0;
  forever begin
    #5;
    clk = ~clk;
  end
end


// ----- DUT -----
cordic #(
  .WIDTH    (WIDTH),
  .FXP_SHIFT(FXP_SHIFT)
)
u_cordic_rtl (
  .angle_in (angle_signed),
  .clock    (clk),
  .cos_out  (cos_out),
  .ready_out(ready_out),
  .reset    (reset),
  .sin_out  (sin_out),
  .start    (start)
);


initial begin
  reset = 1'b1;
  start = 1'b0;
  angle_signed = WIDTH'(0);
  #100;
  reset = 1'b0;
  #100;


  for(int period = 0; period < PERIODS_TO_GENERATE; period++) begin
    for (angle_real = 0; angle_real < (2*PI); angle_real = angle_real + ANGLE_STEP) begin

      angle_signed = $signed(angle_real);

      start = 1'b1;
      #10;
      start = 1'b0;

      wait(ready_out);
      #20;

      $display("Time: %t | Angle: %d deg | Sin: %f | Cos: %f", $time, real'(angle_real * 180/ PI), real'(sin_out)/FXP_SCALE, real'(cos_out)/FXP_SCALE);
    end
  end

  $finish(1);
end


endmodule
