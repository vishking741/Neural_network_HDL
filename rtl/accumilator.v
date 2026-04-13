`timescale 1ns / 1ps

/* * REMARK: This module performs a sequential summation of all products generated 
 * by the multiplier block, followed by the addition of a learned bias value. 
 * To ensure numerical stability and prevent overflow during the summation of 
 * 'N' terms, the output width is expanded by $clog2(N+1) guard bits. 
 *
 * EXTERNAL FILES: The bias value is loaded from 'biasFile'. This file should 
 * contain a single hexadecimal or binary fixed-point value representing the 
 * neuron's offset.
 */

module accumilator #(
    parameter N = 4,            // Number of elements to accumulate
    parameter D_W = 16,         // Original data width
    parameter biasFile = "bias.txt" 
)(
    input clk, 
    input accum_rst,   
    input accum_start,
    input signed [N * 2 * D_W - 1 : 0] accum_in, // Flat string of all products
    // Expanded width: (2 * D_W) for product + guard bits for sum
    output reg signed [2 * D_W + $clog2(N + 1) - 1 : 0] accum_out,
    output reg accum_done
);

    // --- State Machine Definitions ---
    localparam IDLE = 0, ACCUM = 1, ADD_BIAS = 2, DONE = 3;
    reg [1:0] state, next_state;

    reg signed [2*D_W-1:0] mem [0:0];
    initial $readmemb(biasFile, mem);
  
    localparam OUT_W = 2*D_W + $clog2(N+1);
    
    // Internal counter to iterate through the input string
    integer count;

    always @(posedge clk or posedge accum_rst) begin
        if(accum_rst) state <= IDLE;
        else state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case(state)
            IDLE:     if(accum_start) next_state = ACCUM;
            // Stay in ACCUM until all N products are added
            ACCUM:    if(count == N - 1) next_state = ADD_BIAS;
            ADD_BIAS: next_state = DONE;
            DONE:     next_state = IDLE;
            default:  next_state = IDLE;
        endcase
    end

    // --- Accumulation Logic ---
    always @(posedge clk or posedge accum_rst) begin
        if(accum_rst) begin
            accum_done <= 1'b0;
            accum_out <= {OUT_W{1'b0}};
            count <= 0;
        end
        else begin
            case(state)
                IDLE : begin
                    accum_done <= 1'b0;
                    accum_out <= {OUT_W{1'b0}};
                    count <= 0;
                end             
                ACCUM : begin
                    // Sequential Addition: One element per clock cycle
                    accum_out <= accum_out + $signed(accum_in[2*D_W*count +: 2*D_W]);
                    count <= count + 1;
                end
                ADD_BIAS : begin
                    accum_out <= accum_out + $signed(mem[0]);
                end
                DONE : begin
                    accum_done <= 1'b1; 
                end
            endcase
        end
    end
  
endmodule
