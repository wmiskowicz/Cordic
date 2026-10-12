module cordic_pipelined_tb;

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
logic valid_out;


// ----- Clock -----
initial begin
  clk = 1'b0;
  forever begin
    #5;
    clk = ~clk;
  end
end


// ----- DUT -----
cordic_pipelined #(
  .WIDTH    (WIDTH),
  .FXP_SHIFT(FXP_SHIFT)
)
dut (
  .clock    (clk),
  .reset    (reset),
  .ce       (!reset),
  .angle_in (angle_signed),

  .cos_out  (cos_out),
  .sin_out  (sin_out),
  .valid_out(valid_out)
);


// ----- Logging: compare DUT output with reference model -----
// Output appears PIPE_LATENCY clock cycles after the angle is sampled
localparam real MAX_ABS_ERR = 0.02;

reg signed [WIDTH-1:0] angle_hist [$];
reg signed [WIDTH-1:0] angle_exp;
real sin_exp, cos_exp, sin_dut, cos_dut;
int checked = 0;
int mismatches = 0;

always @ (posedge clk) begin
  if (!reset) begin
    angle_hist.push_back(angle_signed);
    if (angle_hist.size() > dut.PIPE_LATENCY) begin
      angle_exp = angle_hist.pop_front();
      sin_exp = $sin(real'(angle_exp) / FXP_SCALE);
      cos_exp = $cos(real'(angle_exp) / FXP_SCALE);
      sin_dut = real'(sin_out) / FXP_SCALE;
      cos_dut = real'(cos_out) / FXP_SCALE;
      checked++;

      if (!valid_out || (sin_dut - sin_exp) > MAX_ABS_ERR || (sin_exp - sin_dut) > MAX_ABS_ERR
                     || (cos_dut - cos_exp) > MAX_ABS_ERR || (cos_exp - cos_dut) > MAX_ABS_ERR) begin
        mismatches++;
        $error("Angle: %0d | Sin: %f (exp %f) | Cos: %f (exp %f) | valid: %b",
               angle_exp, sin_dut, sin_exp, cos_dut, cos_exp, valid_out);
      end
    end
  end
end

final
  $display("Checked %0d samples, %0d mismatches (max abs err %f)", checked, mismatches, MAX_ABS_ERR);


initial begin
  reset = 1'b1;
  angle_signed = WIDTH'(0);
  #100;
  reset = 1'b0;
  #100;


  for(int period = 0; period < PERIODS_TO_GENERATE; period++) begin
    for (angle_real = 0; angle_real < (2*PI); angle_real = angle_real + ANGLE_STEP) begin

      angle_signed = $signed(angle_real);

      wait(valid_out);
      #20;

      $display("Time: %t | Angle: %d deg | Sin: %f | Cos: %f", $time, real'(angle_real * 180/ PI), real'(sin_out)/FXP_SCALE, real'(cos_out)/FXP_SCALE);
    end
  end

  $finish(1);
end


endmodule
