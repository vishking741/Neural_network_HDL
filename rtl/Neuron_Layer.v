`timescale 1ns / 1ps

/* * REMARK: This module acts as a parallel processing container for individual neurons.
 * It uses a 'generate' loop to instantiate multiple Neuron_ASM modules that 
 * compute their outputs simultaneously. The 'layer_done' signal is asserted 
 * only when every individual neuron in the layer has completed its operation, 
 * using a reduction AND operator.
 * * EXTERNAL FILES: This module dynamically generates file names for each neuron 
 * based on the 'LayerNum' and the neuron's index 'i'. It expects weight files 
 * named "w[Layer]_[Neuron].txt" and bias files "b[Layer]_[Neuron].txt". 
 * Note: The current ASCII math (8'h30) supports single-digit indices (0-9) only.
 */

module Neuron_Layer #(
    parameter NUM_NEURONS = 2,
    parameter LayerNum = 1, 
    parameter N = 4, 
    parameter D_W = 16,
    parameter INT_W = 1,
    parameter P = 2
)
(
    input clk,
    input layer_rst,
    input signed [N * D_W - 1 : 0] layer_in,
    input layer_start,
    output [NUM_NEURONS * D_W - 1 : 0] layer_out,
    output layer_done
);
  
    wire [NUM_NEURONS - 1 : 0] done_each;
  
    genvar i;
    generate
        for (i = 0; i < NUM_NEURONS; i = i + 1) begin : gen_neurons
            // Generate ASCII file names (e.g., w1_0.txt)
            localparam W_FILE = {"w", LayerNum[7:0] + 8'h30, "_", i[7:0] + 8'h30, ".txt"};
            localparam B_FILE = {"b", LayerNum[7:0] + 8'h30, "_", i[7:0] + 8'h30, ".txt"};
            
            // Instantiate individual Finite State Machine (ASM) neurons
            Neuron_ASM #(
                .ID(i), 
                .LayerNum(LayerNum), 
                .D_W(D_W), 
                .P(P), 
                .N(N), 
                .INT_W(INT_W), 
                .W_FILE(W_FILE), 
                .B_FILE(B_FILE)
            ) Neuron_inst (
                .clk(clk), 
                .layer_rst(layer_rst), 
                .layer_in(layer_in), 
                .layer_start(layer_start), 
                .neuron_out(layer_out[i*D_W +: D_W]), 
                .neuron_done(done_each[i])
            );
        end
    endgenerate

    // Layer is done only when all neurons are done
    assign layer_done = &done_each;

endmodule