`timescale 1ns / 1ps

/* * REMARK: This Testbench verifies the full top-level 'Neuron_ASM' module.
 * It simulates a single neuron's lifecycle for N=5 inputs using a parallelism 
 * factor of P=2. It covers the full operational chain: 
 * Weight Fetching -> Multiplier -> Accumulation (with Bias) -> Activation.
 *
 * NOTE: Ensure 'weights.txt' contains 5 entries and 'bias.txt' contains 1.
 */

module Neuron_ASM_tb();

    // Parameters matching the system design
    parameter D_W   = 16;
    parameter P     = 2;  
    parameter N     = 5; 
    parameter INT_W = 1;

    // Signal Declarations
    reg clk;
    reg neuron_rst;
    reg neuron_start;
    reg signed [N * D_W - 1 : 0] neuron_in;
    
    wire signed [D_W - 1 : 0] neuron_out;
    wire neuron_done;

    // Device Under Test (DUT) Instantiation
    Neuron_ASM #(
        .D_W(D_W), 
        .P(P), 
        .N(N), 
        .INT_W(INT_W),
        .weightFile("weights.txt"),   
        .biasFile("bias.txt")
    ) dut (
        .clk(clk), 
        .neuron_rst(neuron_rst),
        .neuron_in(neuron_in), 
        .neuron_start(neuron_start),
        .neuron_out(neuron_out), 
        .neuron_done(neuron_done)
    );

    // --- Clock Generation (100MHz) ---
    initial clk = 0;
    always #5 clk = ~clk;

    // --- Stimulus Process ---
    initial begin
        // Reset and Initialization
        neuron_rst = 1;
        neuron_start = 0;
        neuron_in = 0;

        /* * Test Input Vector (5 elements):
         * Mixed signed values to test ReLU and signed multiplication.
         */
        neuron_in[0*16 +: 16] = 16'h3A99;
        neuron_in[1*16 +: 16] = 16'h8195;
        neuron_in[2*16 +: 16] = 16'h0E39;
        neuron_in[3*16 +: 16] = 16'h4587;
        neuron_in[4*16 +: 16] = 16'hFFFF;

        #25 neuron_rst = 0;
        $display("\n--- NEURON SIMULATION START (N=%0d, P=%0d) ---", N, P);
        
        // Trigger Start Handshake
        @(posedge clk);
        neuron_start <= 1;
        @(posedge clk);
        neuron_start <= 0;

        // --- Wait for FSM Completion ---
        wait(neuron_done);
        
        // Results capture
        #1;
        $display("\n--- SIMULATION COMPLETED ---");
        $display("Final Binary Output: %b", neuron_out);
        $display("Final Dec Output:    %0d", $signed(neuron_out));
        
        #50;
        $finish;
    end

endmodule