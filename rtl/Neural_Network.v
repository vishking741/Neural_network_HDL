`timescale 1ns / 1ps

/* * REMARK: This module implements a Feed-Forward Neural Network with 4 Hidden Layers.
 * It uses a Finite State Machine (FSM) to coordinate a sequential handshake protocol; 
 * each layer is triggered only after the previous one asserts its 'done' signal. 
 * Data propagates through dedicated buses (L1_to_L2, etc.), with the final stage 
 * performing an Argmax classification via the Output_Layer.
 *
 * EXTERNAL FILES: Each Neuron_ASM inside the layers requires pre-generated .txt files 
 * for weights and biases. Files must follow the naming convention: "w[Layer]_[Neuron].txt" 
 * and "b[Layer]_[Neuron].txt" (e.g., w1_0.txt, b1_0.txt). These files should contain 
 * hexadecimal fixed-point values corresponding to the D_W and INT_W parameters.
 */

module Neural_Network #(
    parameter D_W = 16, 
    parameter P = 2, 
    parameter INT_W = 1,
    parameter inputNum = 784, 
    parameter outNum = 10
)(
    input clk, network_rst,
    input network_start,
    input [inputNum*D_W - 1 : 0] network_in,
    output [$clog2(outNum) - 1 : 0] network_out,
    output reg network_done
);

    localparam NUM_HIDDEN = 4; 
    localparam num_layer1 = 64; 
    localparam num_layer2 = 32;
    localparam num_layer3 = 16;
    localparam num_layer4 = 16;

    // --- Data Path Wires ---
    wire [inputNum*D_W - 1 : 0] L1_to_L2;
    wire [inputNum*D_W - 1 : 0] L2_to_L3;
    wire [inputNum*D_W - 1 : 0] L3_to_L4;
    wire [inputNum*D_W - 1 : 0] L4_to_OUT;
    
    // --- Control Handshake Signals ---
    wire [NUM_HIDDEN:0] layer_done_sigs;
    reg [NUM_HIDDEN:0] layer_start_sigs;

    // --- State Machine Registers ---
    reg [3:0] state;
    localparam IDLE    = 0,
               LAYER_1 = 1,
               LAYER_2 = 2,
               LAYER_3 = 3,
               LAYER_4 = 4,
               OUT_RUN = 5,
               FINISH  = 6;

    // --- FSM Control Logic with Synchronous Reset ---
    always @(posedge clk) begin
        if (network_rst) begin
            state <= IDLE;
            layer_start_sigs <= 0;
            network_done <= 0;
        end else begin
            case (state)
                IDLE: begin
                    network_done <= 0;
                    if (network_start) begin
                        layer_start_sigs[0] <= 1; // Trigger Hidden Layer 1
                        state <= LAYER_1;
                    end
                end
                LAYER_1: begin
                    if (layer_done_sigs[0]) begin
                        layer_start_sigs[0] <= 0;
                        layer_start_sigs[1] <= 1; // Trigger Hidden Layer 2
                        state <= LAYER_2;
                    end
                end
                LAYER_2: begin
                    if (layer_done_sigs[1]) begin
                        layer_start_sigs[1] <= 0;
                        layer_start_sigs[2] <= 1; // Trigger Hidden Layer 3
                        state <= LAYER_3;
                    end
                end
                LAYER_3: begin
                    if (layer_done_sigs[2]) begin
                        layer_start_sigs[2] <= 0;
                        layer_start_sigs[3] <= 1; // Trigger Hidden Layer 4
                        state <= LAYER_4;
                    end
                end
                LAYER_4: begin
                    if (layer_done_sigs[3]) begin
                        layer_start_sigs[3] <= 0;
                        layer_start_sigs[4] <= 1; // Trigger Output Layer
                        state <= OUT_RUN;
                    end
                end
                OUT_RUN: begin
                    if (layer_done_sigs[4]) begin
                        layer_start_sigs[4] <= 0;
                        state <= FINISH;
                    end
                end
                FINISH: begin
                    network_done <= 1; // Assert global completion
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

    // --- Hidden Layer 1: Input -> L1 ---
    Neuron_Layer #(
        .NUM_NEURONS(num_layer1), 
        .LayerNum(1), 
        .N(inputNum), 
        .D_W(D_W), 
        .P(P)
    ) hid_Layer_1 (
        .clk(clk), 
        .layer_rst(network_rst), 
        .layer_in(network_in), 
        .layer_start(layer_start_sigs[0]), 
        .layer_out(L1_to_L2[num_layer1*D_W-1 : 0]), 
        .layer_done(layer_done_sigs[0])
    );

    // --- Hidden Layer 2: L1 -> L2 ---
    Neuron_Layer #(
        .NUM_NEURONS(num_layer2), 
        .LayerNum(2), 
        .N(num_layer1), 
        .D_W(D_W), 
        .P(P)
    ) hid_Layer_2 (
        .clk(clk), 
        .layer_rst(network_rst), 
        .layer_in(L1_to_L2[num_layer1*D_W-1 : 0]), 
        .layer_start(layer_start_sigs[1]), 
        .layer_out(L2_to_L3[num_layer2*D_W-1 : 0]), 
        .layer_done(layer_done_sigs[1])
    );

    // --- Hidden Layer 3: L2 -> L3 ---
    Neuron_Layer #(
        .NUM_NEURONS(num_layer3), 
        .LayerNum(3), 
        .N(num_layer2), 
        .D_W(D_W), 
        .P(P)
    ) hid_Layer_3 (
        .clk(clk), 
        .layer_rst(network_rst), 
        .layer_in(L2_to_L3[num_layer2*D_W-1 : 0]), 
        .layer_start(layer_start_sigs[2]), 
        .layer_out(L3_to_L4[num_layer3*D_W-1 : 0]), 
        .layer_done(layer_done_sigs[2])
    );

    // --- Hidden Layer 4: L3 -> L4 ---
    Neuron_Layer #(
        .NUM_NEURONS(num_layer4), 
        .LayerNum(4), 
        .N(num_layer3), 
        .D_W(D_W), 
        .P(P)
    ) hid_Layer_4 (
        .clk(clk), 
        .layer_rst(network_rst), 
        .layer_in(L3_to_L4[num_layer3*D_W-1 : 0]), 
        .layer_start(layer_start_sigs[3]), 
        .layer_out(L4_to_OUT[num_layer4*D_W-1 : 0]), 
        .layer_done(layer_done_sigs[3])
    );

    // --- Output Layer: L4 -> Classification ---
    Output_Layer #(
        .N(num_layer4), 
        .D_W(D_W), 
        .P(P), 
        .NUM_NEURONS(outNum)
    ) out_Layer (
        .clk(clk), 
        .layer_rst(network_rst), 
        .layer_in(L4_to_OUT[num_layer4*D_W-1 : 0]), 
        .layer_start(layer_start_sigs[4]), 
        .out_num(network_out), 
        .layer_done(layer_done_sigs[4])
    );

endmodule
