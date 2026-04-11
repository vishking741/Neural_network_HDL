`timescale 1ns / 1ps

/* * REMARK: This Testbench verifies the 'Neuron_Layer' module, which manages 
 * multiple neurons working in parallel. It applies a common input vector 
 * to the entire layer and monitors the 'layer_done' signal, which 
 * should only trigger once every individual neuron in the layer has 
 * finished its computation.
 */

module Layer_TB();

    // Parameters
    parameter NUM_NEURONS = 2;
    parameter N           = 4; 
    parameter D_W         = 16;
    parameter LayerNum    = 1;
    parameter INT_W       = 1;
    parameter P           = 2;

    // Signal Declarations
    reg clk;
    reg layer_rst;
    reg signed [N * D_W - 1 : 0] layer_in;
    reg layer_start;

    wire [NUM_NEURONS * D_W - 1 : 0] layer_out;
    wire layer_done;

    // Device Under Test (DUT) Instantiation
    Neuron_Layer #(
        .NUM_NEURONS(NUM_NEURONS),
        .N(N),
        .D_W(D_W),
        .LayerNum(LayerNum),
        .INT_W(INT_W),
        .P(P)
    ) uut (
        .clk(clk),
        .layer_rst(layer_rst),
        .layer_in(layer_in),
        .layer_start(layer_start),
        .layer_out(layer_out),
        .layer_done(layer_done)
    );

    // --- Clock Generation (100MHz) ---
    initial clk = 0;
    always #5 clk = ~clk;

    // --- Stimulus Process ---
    initial begin
        // Initialize
        layer_rst = 1;
        layer_start = 0;
        layer_in = 0;

        // Reset Sequence
        #25;
        layer_rst = 0;
        #20;

        /* * Set Input Vector: [x3, x2, x1, x0]
         * These 4 inputs are distributed to all neurons in the layer.
         */
        layer_in[0*16 +: 16] = 16'h3A99; // x0
        layer_in[1*16 +: 16] = 16'h8195; // x1
        layer_in[2*16 +: 16] = 16'h0E39; // x2
        layer_in[3*16 +: 16] = 16'h4587; // x3

        // Start Handshake
        @(posedge clk);
        layer_start <= 1;
        @(posedge clk);
        layer_start <= 0;

        // --- Wait for Layer Completion ---
        wait(layer_done);
        
        #20;
        $display("\n--- Layer Simulation Results ---");
        $display("Neuron 0 Output: %h", layer_out[0*D_W +: D_W]);
        $display("Neuron 1 Output: %h", layer_out[1*D_W +: D_W]);
        
        #100;
        $finish;
    end

endmodule