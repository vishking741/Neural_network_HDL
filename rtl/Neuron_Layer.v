`timescale 1ns / 1ps

/* REMARK: This module acts as a parallel processing container for individual neurons.
 * It uses a 'generate' loop to instantiate multiple Neuron_ASM modules that 
 * compute their outputs simultaneously. The 'layer_done' signal is asserted 
 * only when every individual neuron in the layer has completed its operation, 
 * using a reduction AND operator.
 *
 * * EXTERNAL FILES: This module dynamically generates file names for each neuron 
 * based on the 'LayerNum' and the neuron's index 'i'. It expects weight files 
 * named "w[Layer]_[Neuron].txt" and bias files "b[Layer]_[Neuron].txt".
 * The neuron index is formatted as a zero-padded 3-digit number (000-255),
 * enabling support for up to 256 neurons per layer.
 * Example:
 *   w1_000.txt, w1_001.txt, ..., w1_255.txt
 *   b1_000.txt, b1_001.txt, ..., b1_255.txt
 * Note: LayerNum is assumed to be a single digit (<10).
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
        localparam integer HUNDREDS = i / 100;
        localparam integer TENS     = (i % 100) / 10;
        localparam integer ONES     = i % 10;

        localparam integer LAYER_DIGIT = LayerNum; 

        // Ascii conversion
        localparam [7:0] L_CHAR = 8'h30 + LAYER_DIGIT;

        localparam [7:0] H_CHAR = 8'h30 + HUNDREDS;
        localparam [7:0] T_CHAR = 8'h30 + TENS;
        localparam [7:0] O_CHAR = 8'h30 + ONES;

        // File naming
        localparam [8*12-1:0] W_FILE = {
            "w", L_CHAR, "_",
            H_CHAR, T_CHAR, O_CHAR,
            ".txt"
        };

        localparam [8*12-1:0] B_FILE = {
            "b", L_CHAR, "_",
            H_CHAR, T_CHAR, O_CHAR,
            ".txt"
        };

        // Neuron Instantiation
        Neuron_ASM #(
            .neuronNum(i), 
            .layerNum(LayerNum), 
            .D_W(D_W), 
            .P(P), 
            .N(N), 
            .INT_W(INT_W), 
            .weightFile(W_FILE), 
            .biasFile(B_FILE)
        ) Neuron_inst (
            .clk(clk), 
            .neuron_rst(layer_rst), 
            .neuron_in(layer_in), 
            .neuron_start(layer_start), 
            .neuron_out(layer_out[i*D_W +: D_W]), 
            .neuron_done(done_each[i])
        );

    end
endgenerate

    assign layer_done = &done_each;

endmodule    
