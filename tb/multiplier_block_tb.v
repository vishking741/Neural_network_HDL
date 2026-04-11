`timescale 1ns / 1ps

/* * REMARK: This Testbench verifies the 'multiplier_block' by injecting 
 * parallel signed fixed-point data into multiple lanes. It simulates 
 * the control handshake (start/done) and displays the full-precision 
 * 2*D_W results in binary for precise bit-verification.
 */

module multiplier_block_tb;

    // Parameters
    localparam D_W = 16;
    localparam P   = 2;

    // Signal Declarations
    reg clk, mul_rst, mul_start;
    reg  signed [P*D_W-1:0] mul_in1, mul_in2;
    wire signed [P*2*D_W-1:0] mul_out;
    wire mul_valid;

    // Device Under Test (DUT) Instantiation
    multiplier_block #(
        .D_W(D_W), 
        .P(P)
    ) dut (
        .clk(clk),
        .mul_rst(mul_rst),
        .mul_in1(mul_in1),
        .mul_in2(mul_in2),
        .mul_start(mul_start),
        .mul_out(mul_out),
        .mul_done(mul_valid)
    );

    // --- Clock Generation ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // --- Stimulus Process ---
    initial begin
        // Initialize and Reset
        mul_rst = 1; 
        mul_start = 0;
        mul_in1 = 0; 
        mul_in2 = 0;
        #20 mul_rst = 0;

        // --- Test Case 1: Signed Fractional Multiplication ---
        // Lane 1: -0.75 * 0.75  | Lane 0: 0.5 * -0.25
        mul_in1 = { 16'b1010_0000_0000_0000, 16'b0100_0000_0000_0000 };
        mul_in2 = { 16'b0110_0000_0000_0000, 16'b1110_0000_0000_0000 };

        #10 mul_start = 1;
        #10 mul_start = 0;

        wait(mul_valid);
        #1;
        $display("TC1: mul_out = %b", mul_out);
        
        // --- Test Case 2: Hexadecimal Integer Verification ---
        #20;
        mul_in1 = { 16'h0000, 16'h183F };
        mul_in2 = { 16'h0000, 16'h648B };
        
        #10 mul_start = 1;
        #10 mul_start = 0;

        wait(mul_valid);
        #1;
        $display("TC2: mul_out = %b", mul_out);
        
        #50;
        $finish;
    end

endmodule