`timescale 1ns / 1ps

module Neural_Network_tb;

    // ---------- PARAMETERS ----------
    parameter D_W = 16;
    parameter INPUT_NUM = 784;
    parameter OUT_NUM = 10;

    localparam OUT_W = 4; // clog2(10)

    // ---------- SIGNALS ----------
    reg clk;
    reg network_rst;
    reg network_start;

    reg [INPUT_NUM*D_W-1:0] network_in;

    wire [OUT_W-1:0] network_out;
    wire network_done;

    // ---------- INPUT MEMORY ----------
    reg signed [D_W-1:0] input_mem [0:INPUT_NUM-1];

    integer i;

    // ---------- DUT ----------
    Neural_Network dut (
        .clk(clk),
        .network_rst(network_rst),
        .network_start(network_start),
        .network_in(network_in),
        .network_out(network_out),
        .network_done(network_done)
    );

    // ---------- CLOCK ----------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ---------- TEST ----------
    initial begin
        $display("===== NN TEST START =====");

        // Reset
        network_rst = 1;
        network_start = 0;
        network_in = 0;

        // ---------- LOAD INPUT FILE ----------
        $readmemb("digit1_q15.txt", input_mem);

        // ---------- PACK INPUT ----------
        // IMPORTANT: index 0 → LSB
        for (i = 0; i < INPUT_NUM; i = i + 1) begin
            network_in[i*D_W +: D_W] = input_mem[i];
        end

        #20;
        network_rst = 0;

        // ---------- START ----------
        @(posedge clk);
        network_start = 1;

        @(posedge clk);
        network_start = 0;

        // ---------- WAIT ----------
        wait(network_done);

        #10;

        // ---------- OUTPUT ----------
        $display("Prediction = %0d , correct = %d", network_out ,6);

        $display("===== NN TEST END =====");
        $finish;
    end

endmodule
