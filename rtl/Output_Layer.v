`timescale 1ns / 1ps

/* * REMARK: This module serves as the final stage of the Neural Network, acting 
 * as a classifier. It instantiates multiple 'Out_neuron' modules in parallel 
 * and, upon completion, uses a combinational 'Argmax' logic block to identify 
 * the neuron with the highest activation value. The index of this maximum 
 * value (out_num) represents the final predicted class.
 *
 * EXTERNAL FILES: Each Output Neuron expects weight files named "o_w_[i].txt" 
 * and bias files "o_b_[i].txt". These contain pre-trained parameters in 
 * hexadecimal fixed-point format specific to the output layer's dimensions.
 */

module Output_Layer #(
    parameter N = 10,           // Number of inputs from previous layer
    parameter D_W = 16,         // Data Width
    parameter P = 2,            // Parallelism factor
    parameter NUM_NEURONS = 2   // Number of output classes (e.g., 10 for MNIST)
)(
    input clk, layer_rst,
    input signed [N * D_W - 1 : 0] layer_in,
    input layer_start,
    output reg [$clog2(NUM_NEURONS) - 1 : 0] out_num, 
    output layer_done
);
    
    wire [NUM_NEURONS - 1 : 0] done_each;
    
    localparam OUT_W = 2 * D_W + $clog2(N+1);
    
    wire signed [OUT_W - 1 : 0] layer_out [NUM_NEURONS - 1 : 0]; 
    
    // --- Parallel Neuron Instantiation ---
    genvar i;
    generate
        for (i = 0; i < NUM_NEURONS; i = i + 1) begin : gen_neurons
            // Naming convention for output layer parameter files
            localparam W_FILE = {"o_w_", i[7:0] + 8'h30, ".txt"};
            localparam B_FILE = {"o_b_", i[7:0] + 8'h30, ".txt"};
               
            Out_neuron #(
                .ID(i), 
                .D_W(D_W), 
                .P(P), 
                .N(N), 
                .weightFile(W_FILE), 
                .biasFile(B_FILE)
            ) Neuron_inst (
                .clk(clk), 
                .neuron_rst(layer_rst), 
                .neuron_in(layer_in), 
                .neuron_start(layer_start), 
                .neuron_out(layer_out[i]), 
                .neuron_done(done_each[i])
            );
        end
    endgenerate
    
    // Handshake: Global done when all parallel neurons finish
    assign layer_done = &done_each;

    // --- Argmax Logic: Finding the Maximum Activation ---
    integer j;
    reg signed [OUT_W - 1 : 0] max_val;

    always @(*) begin
        if (layer_rst) begin
            out_num = 0;
            max_val = {1'b1, {(OUT_W-1){1'b0}}}; // Initialize with most negative signed value
        end else begin
            max_val = layer_out[0];
            out_num = 0;
            
            // Loop through remaining neurons to find the peak value
            for (j = 1; j < NUM_NEURONS; j = j + 1) begin
                if (layer_out[j] > max_val) begin
                    max_val = layer_out[j];
                    out_num = j[$clog2(NUM_NEURONS)-1 : 0];
                end
            end
        end
    end
    
endmodule