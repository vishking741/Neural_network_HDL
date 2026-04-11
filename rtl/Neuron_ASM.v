`timescale 1ns / 1ps

/* * REMARK: This module (Algorithmic State Machine) represents a single neuron's 
 * computation engine. It processes inputs in chunks of size 'P' to balance 
 * hardware resources and speed. The execution follows a strict sequence: 
 * Weight Fetch (W_F) -> Parallel Multiplication (MUL) -> Global Accumulation (ACC) 
 * -> Activation Function (ACT) -> Completion (DONE).
 *
 * EXTERNAL FILES: This module relies on 'Weight_ROM_mod' to load weights from 
 * 'weightFile' and 'accumulator' to load the bias from 'biasFile'. Both files 
 * should contain hexadecimal fixed-point data.
 */

module Neuron_ASM #(
    parameter neuronNum = 1, 
    parameter layerNum = 1, 
    parameter D_W = 16, 
    parameter P = 2, 
    parameter N = 784, 
    parameter INT_W = 1,
    parameter weightFile = "weights.txt", 
    parameter biasFile = "bias.txt"
)( 
    input clk, neuron_rst,
    input signed [N * D_W - 1 : 0] neuron_in,
    input neuron_start,
    output reg signed [D_W - 1 : 0] neuron_out,
    output reg neuron_done
);
    
    // --- State Machine Definitions ---
    localparam IDLE = 0, W_F = 1, MUL = 2, ACC = 3, ACT = 4, DONE = 5;
    reg [3:0] state, next_state;
    
    localparam A_W = $clog2(N);
    
    // --- Internal Interface Signals ---
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
    
    reg act_start;
    wire act_done;
    wire [D_W-1:0] act_out;
    
    integer i; // Chunk pointer (increments by P)
    integer j; // Bit-slicing index

    // --- Next State Combinational Logic ---
    always @(*) begin
        case(state)
            IDLE : next_state = neuron_start ? W_F : IDLE;
            W_F  : next_state = weight_valid ? MUL : W_F;
            MUL  : if(mul_done) begin
                       if(i + P >= N) next_state = ACC;
                       else next_state = W_F;
                   end else next_state = MUL;
            ACC  : next_state = accum_done ? ACT : ACC;
            ACT  : next_state = act_done ? DONE : ACT;
            DONE : next_state = IDLE;
            default : next_state = IDLE;
        endcase
    end

    // --- Sequential Control Logic with Synchronous Reset ---
    always @(posedge clk) begin
        if(neuron_rst) begin
            state <= IDLE;
            i <= 0;
            accum_in <= 0;
            neuron_done <= 0;
            ren <= 0;
            mul_start <= 0;
            accum_start <= 0;
            act_start <= 0;
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
                    // Slice input vector into chunks for the multiplier
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
                        // Map multiplier outputs back to the wide accumulation register
                        for (j = 0; j < P; j = j + 1) begin 
                            if (i + j < N) 
                                accum_in[(i + j)*2*D_W +: 2*D_W] <= mul_out[(P-1-j)*2*D_W +: 2*D_W];
                        end
                        i <= i + P;
                    end
                end

                ACC : begin
                    accum_start <= 1; // Trigger Summation + Bias addition
                end

                ACT : begin
                    accum_start <= 0;
                    act_start <= 1;   // Trigger ReLU/Sigmoid activation
                    if (act_done) begin
                        act_start <= 0;
                        neuron_out <= act_out;
                    end
                end

                DONE : begin
                    neuron_done <= 1; // Pulse high to signal layer completion
                end
            endcase
        end
    end

    // --- Component Instantiations ---
    Weight_ROM_mod #(weightFile, N, P, D_W, A_W) ROM_inst 
        (clk, ren, start_add, weight_string, weight_valid);

    multiplier_block #(D_W, P) Mul_inst
        (clk, neuron_rst, mul_in1, mul_in2, mul_start, mul_out, mul_done);

    accumilator #(N, D_W, biasFile) accum_inst
        (clk, neuron_rst, accum_start, accum_in, accum_out, accum_done);

    activation #(D_W , INT_W , N) activation_inst
        (clk, act_start, accum_out, act_done, act_out);

endmodule