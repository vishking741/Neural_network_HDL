`timescale 1ns / 1ps

/* * REMARK: This Testbench verifies the 'activation' module using a direct 
 * procedural block instead of helper tasks. It manually handles the 
 * act_start/act_done handshake for various corner cases including 
 * negative values (ReLU) and overflow values (Saturation).
 */

module activation_tb;

    // Parameters
    parameter D_W   = 16;
    parameter INT_W = 1;
    parameter N     = 20;
    localparam IN_W = (2 * D_W) + $clog2(N + 1);

    // Signal Declarations
    reg clk;
    reg act_start;
    reg signed [IN_W-1:0] act_in; 

    wire act_done;
    wire [D_W-1:0] act_out;

    // Device Under Test (DUT) Instantiation
    activation #(
        .D_W(D_W),
        .INT_W(INT_W),
        .N(N)
    ) dut (
        .clk(clk),
        .act_start(act_start),
        .act_in(act_in),
        .act_done(act_done),
        .act_out(act_out)
    );

    // --- Clock Generation ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // --- Stimulus Process ---
    initial begin
        // Initialize Signals
        act_start = 0; 
        act_in = 0;
        #20;

        $display("\n--- RELU + SATURATION VERIFICATION (Manual Handshake) ---");

        // --- Test Case 1: Negative Input (Expect Output: 0) ---
        @(posedge clk);
        act_in    <= -50000;
        act_start <= 1'b1;
        @(posedge clk);
        act_start <= 1'b0;
        wait (act_done);
        $display("TC1 | Input: %0d | Output: %h", $signed(act_in), act_out);

        // --- Test Case 2: Positive Input (Expect Output: Normal Scale) ---
        #10;
        @(posedge clk);
        act_in    <= 35'h20000000; 
        act_start <= 1'b1;
        @(posedge clk);
        act_start <= 1'b0;
        wait (act_done);
        $display("TC2 | Input: %0d | Output: %h", $signed(act_in), act_out);

        // --- Test Case 3: Over-saturation (Expect Output: 7FFF) ---
        #10;
        @(posedge clk);
        act_in    <= 35'h40000000; 
        act_start <= 1'b1;
        @(posedge clk);
        act_start <= 1'b0;
        wait (act_done);
        $display("TC3 | Input: %0d | Output: %h (Saturated)", $signed(act_in), act_out);

        // --- Test Case 4: Maximum Positive Range ---
        #10;
        @(posedge clk);
        act_in    <= 35'h7FFFFFFFF; 
        act_start <= 1'b1;
        @(posedge clk);
        act_start <= 1'b0;
        wait (act_done);
        $display("TC4 | Input: %0d | Output: %h", $signed(act_in), act_out);

        #50;
        $finish;
    end

endmodule