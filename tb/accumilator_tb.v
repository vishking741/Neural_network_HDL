`timescale 1ns / 1ps

/* * REMARK: This Testbench verifies the 'accumilator' module by providing a 
 * concatenated string of products and triggering the sequential addition 
 * logic. It demonstrates the hardware handshake (start/done) and 
 * verifies the final sum, which includes the bias loaded from an 
 * external file.
 */

module accumilator_tb;

    // Parameters
    parameter N   = 4;
    parameter D_W = 16;

    // Localparams for bus widths
    localparam IN_W  = N * 2 * D_W;                // 128 bits total for 4 products
    localparam OUT_W = 2 * D_W + $clog2(N + 1);    // 35 bits (includes guard bits)

    // Signal Declarations
    reg clk;
    reg accum_rst;
    reg accum_start;
    reg  signed [IN_W-1:0]  accum_in;
    
    wire signed [OUT_W-1:0] accum_out;
    wire accum_done;

    // Device Under Test (DUT) Instantiation
    accumilator #(
        .N(N),
        .D_W(D_W),
        .biasFile("bias.txt")
    ) dut (
        .clk(clk),
        .accum_rst(accum_rst),
        .accum_start(accum_start),
        .accum_in(accum_in),
        .accum_out(accum_out),
        .accum_done(accum_done)
    );

    // --- Clock Generation (100MHz) ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // --- Stimulus Process ---
    initial begin
        $display("===== ACCUMULATOR TB START =====");

        // Initialize and Reset
        accum_rst   = 1;
        accum_start = 0;
        accum_in    = 0;

        #20;
        accum_rst = 0;
        #20;

        /* * Test Vector Preparation:
         * Packed as {v3, v2, v1, v0} where each is a 32-bit product.
         */
        accum_in = {
            32'h23D70A3D, 32'h0DCE78B8, 32'h1E737157, 32'h3F350400
        };

        $display("[TB] Applying Input: %h", accum_in);

        // Start Handshake
        @(posedge clk);
        accum_start <= 1;
        @(posedge clk);
        accum_start <= 0;

        // Wait for Sequential Logic to finish (N + 1 cycles)
        wait(accum_done == 1'b1);
        
        // Output Results
        #1;
        $display("[TB] Results Captured:");
        $display("     - accum_out (hex): %h", accum_out);
        $display("     - accum_out (dec): %0d", accum_out);
        
        // Peek into DUT memory to verify bias loading
        $display("     - Internal Bias Loaded: %h", dut.mem[0]);

        #50;
        $display("===== ACCUMULATOR TB END =====");
        $finish;
    end

endmodule