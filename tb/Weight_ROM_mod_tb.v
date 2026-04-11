`timescale 1ns / 1ps

/* * REMARK: This Testbench verifies the 'Weight_ROM_mod' functionality.
 * It simulates consecutive read operations from different memory addresses 
 * to ensure that the parallel weight fetch (P weights per read) correctly 
 * packages the data into the output string.
 */

module Weight_ROM_mod_tb;

    // Parameters
    localparam P   = 2;
    localparam D_W = 16;
    localparam A_W = 2;
    localparam N   = 4; // Assuming N=4 for full address range test

    // Signal Declarations
    reg clk;
    reg ren;
    reg [A_W-1:0] start_add;
    wire [P*D_W-1:0] weight_string;
    wire weight_valid;

    // Device Under Test (DUT) Instantiation
    Weight_ROM_mod #(
        .weightFile("weights.txt"),
        .P(P),
        .D_W(D_W),
        .A_W(A_W),
        .N(N)
    ) dut (
        .clk(clk),
        .ren(ren),
        .start_add(start_add),
        .weight_string(weight_string),
        .weight_valid(weight_valid)
    );

    // --- Clock Generation (100 MHz) ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // --- Stimulus Process ---
    initial begin
        $display("Starting Weight_ROM_mod TB...");
        
        // Initial State
        ren       = 0;
        start_add = 0;
        #20;

        // READ 1: Fetch {mem[0], mem[1]}
        @(posedge clk);
        start_add <= 0;
        ren <= 1;
        @(posedge clk);
        ren <= 0;
        wait(weight_valid);
        
        // READ 2: Fetch {mem[1], mem[2]}
        #40;
        @(posedge clk);
        start_add <= 1;
        ren <= 1;
        @(posedge clk);
        ren <= 0;
        wait(weight_valid);

        // READ 3: Fetch {mem[2], mem[3]}
        #40;
        @(posedge clk);
        start_add <= 2;
        ren <= 1;
        @(posedge clk);
        ren <= 0;
        wait(weight_valid);

        #50;
        $finish;
    end

    // --- Monitor ---
    initial begin
        $monitor("T=%0t | ren=%b addr=%d | valid=%b | string=%b",
                 $time, ren, start_add, weight_valid, weight_string);
    end

endmodule