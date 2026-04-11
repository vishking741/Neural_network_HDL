`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/21/2025 03:17:40 PM
// Design Name: 
// Module Name: Out_neuron_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns / 1ps

module Out_neuron_tb();

    // Parameters
    
    parameter N = 5;          // Number of inputs
    parameter D_W = 16;        // Data width
    parameter P = 2;           // Parallelism factor
    parameter weightFile = "weights.txt";
    parameter biasFile = "bias.txt";

    // Inputs
    reg clk;
    reg neuron_rst;
    reg signed [N * D_W - 1 : 0] neuron_in;
    reg neuron_start;

    // Outputs
    wire signed [2 * D_W + $clog2(N+1) - 1 : 0] neuron_out;
    wire neuron_done;

    // Instantiate the Unit Under Test (UUT)
    Out_neuron #(
        .neuronNum(0),
        .D_W(D_W),
        .P(P),
        .N(N),
        .weightFile(weightFile),
        .biasFile(biasFile)
    ) uut (
        .clk(clk), 
        .neuron_rst(neuron_rst), 
        .neuron_in(neuron_in), 
        .neuron_start(neuron_start), 
        .neuron_out(neuron_out), 
        .neuron_done(neuron_done)
    );

    // Clock generation (100MHz)
    always #5 clk = ~clk;

    // Helper to pack values into the wide input vector
    integer k;
    task set_inputs;
        input signed [D_W-1:0] val;
        begin
            for (k = 0; k < N; k = k + 1) begin
                neuron_in[k*D_W +: D_W] = val + k; // Assigns sequential test values
            end
        end
    endtask

    initial begin
        // Initialize Inputs
        clk = 0;
        neuron_rst = 1;
        neuron_in = 0;
        neuron_start = 0;

        // Reset system
        #20;
        neuron_rst = 0;
        #20;

        // 1. Prepare test data (e.g., all inputs set to '2' + index)
        set_inputs(16'sd2);
        
        // 2. Start the neuron operation
        @(posedge clk);
        neuron_start = 1;
        @(posedge clk);
        neuron_start = 0;

        // 3. Wait for completion
        wait(neuron_done);
        
        // Display result
        $display("Neuron calculation finished!");
        $display("Final Output: %b", neuron_out);
        
        #100;
        $stop;
    end

endmodule
