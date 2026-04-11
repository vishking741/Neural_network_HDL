`timescale 1ns / 1ps

/* * REMARK: This module performs parallel signed multiplication for 'P' pairs of 
 * data simultaneously. It takes two concatenated input strings (mul_in1 and mul_in2) 
 * and generates a wide output string containing the full-precision products. 
 * This parallel approach significantly reduces the clock cycles required to 
 * process large vectors in the hidden and output layers.
 * * NOTE: The multiplication occurs in the MUL state, and the result is available 
 * when 'mul_done' pulses high in the following cycle. 
 */

module multiplier_block #(
    parameter D_W = 16, // Input bit width
    parameter P = 2     // Number of parallel multiplications
)(
    input  clk,
    input  mul_rst,
    input signed [P*D_W-1:0]       mul_in1,
    input signed [P*D_W-1:0]       mul_in2,
    input  mul_start,
    output reg signed [P*2*D_W-1:0] mul_out,
    output reg                       mul_done
);

    // --- State Machine Definitions ---
    localparam IDLE = 0,
               MUL  = 1,
               DONE = 2;

    reg [1:0] state, next_state;

    // --- State Register Logic ---
    always @(posedge clk or posedge mul_rst) begin
        if (mul_rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    // --- Next State Combinational Logic ---
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: if (mul_start) next_state = MUL;
            MUL :                next_state = DONE; // Single cycle multiplication
            DONE:                next_state = IDLE;
            default:             next_state = IDLE;
        endcase
    end

    // --- Control Signal Logic ---
    always @(posedge clk or posedge mul_rst) begin
        if (mul_rst)
            mul_done <= 1'b0;
        else begin
            case (state)
                IDLE: mul_done <= 1'b0;
                MUL : mul_done <= 1'b0;
                DONE: mul_done <= 1'b1; // Result is stable here
                default: mul_done <= 1'b0;
            endcase
        end
    end

    // --- Parallel Multiplier Instantiation ---
    genvar i;
    generate
        for (i = 0; i < P; i = i + 1) begin : MULTIPLY_BLOCK
            always @(posedge clk or posedge mul_rst) begin
                if (mul_rst)
                    mul_out[2*D_W*(i+1)-1 : 2*D_W*i] <= {2*D_W{1'b0}};
                else if (state == MUL)
                    /* * Full-precision signed multiplication: 
                     * Result width is 2 * D_W to avoid overflow.
                     */
                    mul_out[2*D_W*(i+1)-1 : 2*D_W*i] <=
                        $signed(mul_in1[D_W*(i+1)-1 : D_W*i]) *
                        $signed(mul_in2[D_W*(i+1)-1 : D_W*i]);
            end
        end
    endgenerate

endmodule