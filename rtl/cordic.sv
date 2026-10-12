module cordic #(
  parameter integer WIDTH = 16,
  parameter FXP_SHIFT = 10
)(
  input wire clock,
  input wire reset,
  input wire start,
  input wire signed [WIDTH-1:0] angle_in,

  output logic ready_out,
  output logic signed [WIDTH-1:0] sin_out,
  output logic signed [WIDTH-1:0] cos_out
);

// ----- Local parameters -----
localparam FXP_MUL = 2**FXP_SHIFT;
localparam KN = get_kn(FXP_SHIFT+1, FXP_MUL);
localparam PI = int'(3.14 * FXP_MUL);

const reg signed [WIDTH-1:0] atan [0:10] = {
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

// ----- FSM states -----
typedef enum bit [3:0] {
  S1 = 4'h01,
  S2 = 4'h02,
  S3 = 4'h03,
  S4 = 4'h04,
  S5 = 4'h05,
  S6 = 4'h06
} state_t;

state_t state;


// ----- Local variables -----
integer sign_x, sign_y;
reg signed [WIDTH-1:0] angle_q, angle_inner;
reg signed [WIDTH-1:0] cos_inner, sin_inner;
reg signed [WIDTH-1:0] x_shift, y_shift;
reg [3:0] i;

always_ff @ (posedge clock) begin
  if(reset) begin
    ready_out <= 1'b0;
    sin_out   <= WIDTH'(0);
    cos_out   <= WIDTH'(0);

    state <= S1;
    angle_inner <= WIDTH'(0);
    cos_inner <= KN;
    sin_inner <= WIDTH'(0);
    x_shift <= WIDTH'(0);
    y_shift <= WIDTH'(0);
    i <= 4'd0;
  end
  else begin
    case(state)
      S1: begin
        if (start) begin
          state   <= S2;
          angle_q <= angle_in;
          ready_out <= 1'b0;
          angle_inner <= WIDTH'(0);
          i <= 4'd0;
          sign_x <= 1;
          sign_y <= 1;
        end
      end

      S2: begin
        // 90 to 270 degrees
        if (angle_q > (PI/2) && angle_q <= (3 * (PI/2))) begin
          angle_q <= angle_q - PI;
          sign_x <= -1;
          sign_y <= -1;
        end
        // 270 to 360 degrees
        else if (angle_q > (3 * (PI/2))) begin
          angle_q <= angle_q - 2*PI;
          sign_x <= 1;
          sign_y <= 1;
        end

        cos_inner <= KN;
        sin_inner <= WIDTH'(0);
        angle_inner <= WIDTH'(0);

        state <= S3;
      end

      S3: begin
        if (i < FXP_SHIFT+1) begin
          state <= S3;
          i <= i + 4'd1;


          // Use blocking assignment to get value on the same clock cycle
          x_shift = cos_inner >>> i;
          y_shift = sin_inner >>> i;

          if (angle_q > angle_inner) begin
            angle_inner <= angle_inner + atan[i];
            cos_inner   <= cos_inner - y_shift;
            sin_inner   <= sin_inner + x_shift;
          end
          else begin
            angle_inner <= angle_inner - atan[i];
            cos_inner   <= cos_inner + y_shift;
            sin_inner   <= sin_inner - x_shift;
          end
        end
        else begin
          state <= S4;
        end

      end

      S4: begin
        cos_out   <= (sign_x == -1) ? -cos_inner : cos_inner;
        sin_out   <= (sign_y == -1) ? -sin_inner : sin_inner;
        ready_out <= 1'b1;
        state <= S5;
      end

      S5: begin
        state <= !start ? S1 : S5;
      end

      default:
        state <= S1;

    endcase
  end
end


function automatic int get_kn(int iterations, int scale);
  case (iterations)
    1:  return int'(0.707107 * scale);
    2:  return int'(0.632456 * scale);
    3:  return int'(0.613572 * scale);
    4:  return int'(0.608834 * scale);
    5:  return int'(0.607648 * scale);
    default: return int'(0.607253 * scale); // Covers everything 6 and up
  endcase
endfunction


endmodule
