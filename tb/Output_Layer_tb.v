`timescale 1ns / 1ps

/* * REMARK: This Testbench verifies the 'Output_Layer' module, which typically 
 * contains the final classification logic (e.g., an Argmax operation). 
 * It applies a uniform input vector and monitors the 'out_num' signal 
 * to identify which neuron index "won" the classification based on 
 * the loaded weights and biases.
 */

module Output_Layer_tb();
    parameter N           = 5;   // Inputs from previous layer
    parameter D_W         = 16;  // Data bit-width
    parameter P           = 2;   // Parallelism factor
    parameter NUM_NEURONS = 2;   // Number of classes/output neurons

    // Signal Declarations
    reg clk;
    reg layer_rst;
    reg signed [N * D_W - 1 : 0] layer_in;
    reg layer_start;

    wire [$clog2(NUM_NEURONS) - 1 : 0] out_num; // Classification result index
    wire layer_done;

    Output_Layer #(
        .N(N), 
        .D_W(D_W), 
        .P(P), 
        .NUM_NEURONS(NUM_NEURONS)
    ) uut (
        .clk(clk), 
        .layer_rst(layer_rst), 
        .layer_in(layer_in), 
        .layer_start(layer_start), 
        .out_num(out_num), 
        .layer_done(layer_done)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // --- Stimulus Process ---
    initial begin
        // Initialize
        layer_rst   = 1;
        layer_start = 0;
        layer_in    = 0;

        #100;
        layer_rst = 0;
        #20;

        /* * Test Input Vector:
         * Loading all 5 inputs with a maximum positive fixed-point value (1.0).
         */
        layer_in = {5{16'sh7FFF}}; 

        // Start Handshake
        @(posedge clk);
        layer_start <= 1;
        @(posedge clk);
        layer_start <= 0;

        // --- Wait for Classification Completion ---
        wait(layer_done == 1'b1);
        
        #20;
        $display("\n--- Output Layer Simulation Result ---");
        $display("Final Winning Neuron Index: %d", out_num);
        
        #100;
        $stop;
    end

endmodule