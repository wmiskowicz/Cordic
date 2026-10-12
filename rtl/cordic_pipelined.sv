// ----------------------------------------------------------------------------
// Single CORDIC rotation step (one pipeline stage)
// ----------------------------------------------------------------------------
module cordic_step #(
  parameter integer WIDTH = 16,
  parameter integer STEP  = 0
)(
  input wire clock,
  input wire ce,
  input wire signed [WIDTH-1:0] sin_in,
  input wire signed [WIDTH-1:0] cos_in,
  input wire signed [WIDTH-1:0] angle_in,
  input wire signed [WIDTH-1:0] t_angle_in,
  input wire                    negate_in,
  input wire signed [WIDTH-1:0] atan,

  output logic signed [WIDTH-1:0] sin_out,
  output logic signed [WIDTH-1:0] cos_out,
  output logic signed [WIDTH-1:0] angle_out,
  output logic signed [WIDTH-1:0] t_angle_out,
  output logic                    negate_out
);

always_ff @ (posedge clock) begin
  if (ce) begin
    // Arithmetic shift - operands must be signed
    if (t_angle_in > angle_in) begin
      cos_out   <= cos_in - (sin_in >>> STEP);
      sin_out   <= sin_in + (cos_in >>> STEP);
      angle_out <= angle_in + atan;
    end
    else begin
      cos_out   <= cos_in + (sin_in >>> STEP);
      sin_out   <= sin_in - (cos_in >>> STEP);
      angle_out <= angle_in - atan;
    end

    // Pass-through values travelling with the data
    t_angle_out <= t_angle_in;
    negate_out  <= negate_in;
  end
end

endmodule


// ----------------------------------------------------------------------------
// Multiplication by constant Kn = 0.607 (621/1024) using shift-and-add
//   Kn * 1024 = 1 - 4 + 16 - 32 + 128 + 512 = 621
// ----------------------------------------------------------------------------
module mul_kn #(
  parameter integer WIDTH = 16,
  parameter FXP_SHIFT = 10
)(
  input wire clock,
  input wire ce,
  input wire signed [WIDTH-1:0] value_in,

  output logic signed [WIDTH-1:0] value_out
);

// ----- Local parameters -----
localparam LATENCY = 5;

// ----- Local variables -----
// Shifted values of the input
logic signed [2*WIDTH-1:0] val;
logic signed [2*WIDTH-1:0] val_0, val_2, val_4, val_5, val_7, val_9;
// Accumulated shifted values
logic signed [2*WIDTH-1:0] val_0_2, val_4_5, val_7_9, val_7_9_d;
logic signed [2*WIDTH-1:0] val_0_2_4_5, val_0_2_4_5_7_9;

assign val = value_in; // Sign extension to 2*WIDTH

always_ff @ (posedge clock) begin
  if (ce) begin
    // Pipe stage 1 - shifts
    val_0 <= val;
    val_2 <= val <<< 2;
    val_4 <= val <<< 4;
    val_5 <= val <<< 5;
    val_7 <= val <<< 7;
    val_9 <= val <<< 9;

    // Pipe stage 2 - pairwise sums
    val_0_2 <= val_0 - val_2;
    val_4_5 <= val_4 - val_5;
    val_7_9 <= val_7 + val_9;

    // Pipe stage 3
    val_0_2_4_5 <= val_0_2 + val_4_5;
    val_7_9_d   <= val_7_9;

    // Pipe stage 4
    val_0_2_4_5_7_9 <= val_0_2_4_5 + val_7_9_d;

    // Pipe stage 5 - normalise
    value_out <= WIDTH'(val_0_2_4_5_7_9 >>> FXP_SHIFT);
  end
end

endmodule


// ----------------------------------------------------------------------------
// Pipelined CORDIC - one sin/cos result per clock cycle
//   angle_in range: 0 .. 2*PI (fixed-point, FXP_SHIFT fractional bits)
// ----------------------------------------------------------------------------
module cordic_pipelined #(
  parameter integer WIDTH = 16,
  parameter FXP_SHIFT = 10
)(
  input wire clock,
  input wire reset,
  input wire ce,
  input wire signed [WIDTH-1:0] angle_in,

  output logic signed [WIDTH-1:0] sin_out,
  output logic signed [WIDTH-1:0] cos_out,
  output logic valid_out
);

// ----- Local parameters -----
localparam FXP_MUL = 2**FXP_SHIFT;
localparam PI = int'(3.14 * FXP_MUL);
localparam STEPS = FXP_SHIFT + 1;
localparam MUL_KN_LATENCY = 5;
// Quadrant reduction + CORDIC steps + Kn scaling + output sign correction
localparam PIPE_LATENCY = 1 + STEPS + MUL_KN_LATENCY + 1;

const logic signed [WIDTH-1:0] atan [0:10] = {
  12'b001100100100,
  12'b000111011011,
  12'b000011111011,
  12'b000001111111,
  12'b000001000000,
  12'b000000100000,
  12'b000000010000,
  12'b000000001000,
  12'b000000000100,
  12'b000000000010,
  12'b000000000001
};


// ----- Local variables -----
// Connections between pipeline steps
logic signed [WIDTH-1:0] sin_tab     [0:STEPS];
logic signed [WIDTH-1:0] cos_tab     [0:STEPS];
logic signed [WIDTH-1:0] angle_tab   [0:STEPS];
logic signed [WIDTH-1:0] t_angle_tab [0:STEPS]; // Target angle must be pipelined
logic                    negate_tab  [0:STEPS]; // Quadrant sign must be pipelined

logic signed [WIDTH-1:0] sin_scaled, cos_scaled;
logic [MUL_KN_LATENCY-1:0] negate_dly;
logic [7:0] valid_cnt;


// ----- Stage 0: quadrant reduction -----
always_ff @ (posedge clock) begin
  if (ce) begin
    // 90 to 270 degrees
    if (angle_in > (PI/2) && angle_in <= (3 * (PI/2))) begin
      t_angle_tab[0] <= angle_in - PI;
      negate_tab[0]  <= 1'b1;
    end
    // 270 to 360 degrees
    else if (angle_in > (3 * (PI/2))) begin
      t_angle_tab[0] <= angle_in - 2*PI;
      negate_tab[0]  <= 1'b0;
    end
    else begin
      t_angle_tab[0] <= angle_in;
      negate_tab[0]  <= 1'b0;
    end
  end
end

assign cos_tab[0]   = WIDTH'(FXP_MUL);
assign sin_tab[0]   = WIDTH'(0);
assign angle_tab[0] = WIDTH'(0);


// ----- CORDIC rotation pipeline -----
genvar i;
generate
  for (i = 0; i < STEPS; i++) begin : g_step
    cordic_step #(
      .WIDTH(WIDTH),
      .STEP (i)
    )
    u_cordic_step (
      .clock      (clock),
      .ce         (ce),
      .sin_in     (sin_tab[i]),
      .cos_in     (cos_tab[i]),
      .angle_in   (angle_tab[i]),
      .t_angle_in (t_angle_tab[i]),
      .negate_in  (negate_tab[i]),
      .atan       (atan[i]),

      .sin_out    (sin_tab[i+1]),
      .cos_out    (cos_tab[i+1]),
      .angle_out  (angle_tab[i+1]),
      .t_angle_out(t_angle_tab[i+1]),
      .negate_out (negate_tab[i+1])
    );
  end
endgenerate


// ----- Results scaling -----
mul_kn #(
  .WIDTH    (WIDTH),
  .FXP_SHIFT(FXP_SHIFT)
)
u_mul_kn_sin (
  .clock    (clock),
  .ce       (ce),
  .value_in (sin_tab[STEPS]),
  .value_out(sin_scaled)
);

mul_kn #(
  .WIDTH    (WIDTH),
  .FXP_SHIFT(FXP_SHIFT)
)
u_mul_kn_cos (
  .clock    (clock),
  .ce       (ce),
  .value_in (cos_tab[STEPS]),
  .value_out(cos_scaled)
);


// ----- Output stage: quadrant sign correction + valid -----
always_ff @ (posedge clock) begin
  if (reset) begin
    sin_out    <= WIDTH'(0);
    cos_out    <= WIDTH'(0);
    negate_dly <= '0;
    valid_cnt  <= 8'(PIPE_LATENCY);
  end
  else if (ce) begin
    // Delay the quadrant sign by the latency of mul_kn
    negate_dly <= {negate_dly[MUL_KN_LATENCY-2:0], negate_tab[STEPS]};

    sin_out <= negate_dly[MUL_KN_LATENCY-1] ? -sin_scaled : sin_scaled;
    cos_out <= negate_dly[MUL_KN_LATENCY-1] ? -cos_scaled : cos_scaled;

    // Count down until the pipe is full
    if (valid_cnt != 0)
      valid_cnt <= valid_cnt - 8'd1;
  end
end

assign valid_out = (valid_cnt == 0);

endmodule
