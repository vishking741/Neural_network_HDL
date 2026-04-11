`timescale 1ns / 1ps

/* * REMARK: This module implements the computation logic for a single neuron 
 * specifically for the Output Layer. Unlike the standard hidden layer neuron, 
 * this version omits the non-linear activation function (ReLU) to allow 
 * the Argmax logic in the Output_Layer module to compare raw activation 
 * values (logits). It follows a chunk-based processing flow: 
 * Weight Fetch -> Multiplier -> Accumulator -> Done.
 *
 * EXTERNAL FILES: Operates using 'Weight_ROM_mod' for 'weightFile' and 
 * 'accumulator' for 'biasFile'. These files should contain the trained 
 * floating-point weights converted to the project's fixed-point format.
 */

module Out_neuron #(
    parameter neuronNum = 1, 
    parameter D_W = 16, 
    parameter P = 2, 
    parameter N = 784,
    parameter weightFile = "weights.txt", 
    parameter biasFile = "bias.txt"
)
( 
    input clk, neuron_rst,
    input signed [N * D_W - 1 : 0] neuron_in,
    input neuron_start,
    // Output width includes guard bits for high-precision summation
    output reg signed [2 * D_W + $clog2(N+1) - 1 : 0] neuron_out,
    output reg neuron_done
);
    
    // --- State Machine Definitions ---
    localparam IDLE = 0, W_F = 1, MUL = 2, ACC = 3, DONE = 4;
    reg [3:0] state, next_state;
    
    localparam A_W = $clog2(N);
    
    // --- Internal Control & Data Signals ---
    reg ren;
    reg [A_W - 1 : 0] start_add;
    wire signed [P * D_W - 1 : 0] weight_string;
    wire weight_valid;
    
    reg mul_start;
    reg signed [P * D_W - 1 : 0] mul_in1, mul_in2;
    wire signed [P * 2 * D_W - 1 : 0] mul_out;
    wire mul_done; 
    
    reg accum_start;
    reg signed [N * 2 * D_W - 1 : 0] accum_in;
    wire signed [2 * D_W + $clog2(N+1) - 1 : 0] accum_out;
    wire accum_done;
    
    integer i; // Chunk pointer
    integer j; // Slicing loop index

    // --- Next State Logic ---
    always @(*) begin
        case(state)
            IDLE : next_state = neuron_start ? W_F : IDLE;
            W_F  : next_state = weight_valid ? MUL : W_F;
            MUL  : if(mul_done) begin
                       if(i + P >= N) next_state = ACC;
                       else next_state = W_F;
                   end else next_state = MUL;
            ACC  : next_state = accum_done ? DONE : ACC;
            DONE : next_state = IDLE;
            default : next_state = IDLE;
        endcase
    end

    // --- State Execution & Control Logic ---
    always @(posedge clk or posedge neuron_rst) begin
        if(neuron_rst) begin
            state <= IDLE;
            i <= 0;
            accum_in <= 0;
            neuron_done <= 0;
            ren <= 0;
            mul_start <= 0;
            accum_start <= 0;
            neuron_out <= 0;
        end
        else begin
            state <= next_state;
            case(state)
                IDLE : begin
                    i <= 0;
                    neuron_done <= 0;
                    accum_in <= 0;
                end

                W_F : begin
                    ren <= 1;
                    start_add <= i; 
                    for (j = 0; j < P; j = j + 1) begin
                        if (i + j < N)
                            mul_in1[(P-1-j)*D_W +: D_W] <= neuron_in[(i + j)*D_W +: D_W];
                        else
                            mul_in1[(P-1-j)*D_W +: D_W] <= {D_W{1'b0}}; 
                    end
                end

                MUL : begin 
                    ren <= 0; 
                    mul_start <= 1; 
                    mul_in2 <= weight_string; 

                    if (mul_done) begin 
                        mul_start <= 0; 
                        for (j = 0; j < P; j = j + 1) begin 
                            if (i + j < N) 
                                accum_in[(i + j)*2*D_W +: 2*D_W] <= mul_out[(P-1-j)*2*D_W +: 2*D_W];
                        end
                        i <= i + P;
                    end
                end

                ACC : begin
                    accum_start <= 1;
                    if(accum_done) begin
                      accum_start <= 0;
                      neuron_out <= accum_out; // Raw sum + bias passed to Output_Layer
                    end
                end

                DONE : begin
                    neuron_done <= 1;
                end
            endcase
        end
    end

    // --- Sub-module Instantiations ---
    Weight_ROM_mod #(weightFile, N, P, D_W, A_W) ROM_inst 
        (clk, ren, start_add, weight_string, weight_valid);

    multiplier_block #(D_W, P) Mul_inst
        (clk, neuron_rst, mul_in1, mul_in2, mul_start, mul_out, mul_done);

    accumilator #(N, D_W, biasFile) accum_inst
        (clk, neuron_rst, accum_start, accum_in, accum_out, accum_done);

endmodule