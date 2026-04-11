`timescale 1ns / 1ps

/* * REMARK: This module implements the ReLU (Rectified Linear Unit) activation 
 * function with added hardware saturation logic. 
 * 1. ReLU: If the input is negative, the output is forced to 0.
 * 2. Saturation: If the accumulation result exceeds the maximum representable 
 * value for the target D_W (integer overflow), it caps the output at the 
 * maximum positive value rather than allowing a wrap-around error.
 * 3. Truncation: It aligns and extracts the relevant bits from the high-precision 
 * product (2*D_W) back to the standard D_W format using the INT_W parameter.
 */

module activation #(
    parameter D_W   = 16,
    parameter INT_W = 1,
    parameter N     = 20
)(
    input                          clk,
    input                          act_start,
    input signed [(2 * D_W) + $clog2(N + 1) - 1:0]   act_in,
    output reg                     act_done,
    output reg [D_W-1:0]           act_out
);

    // --- State Machine Definitions ---
    localparam IDLE    = 2'b00;
    localparam PROCESS = 2'b01;
    localparam FINISH  = 2'b10;

    // Fixed-point alignment constants
    localparam FRAC_W     = D_W - INT_W; 
    localparam ACC_FRAC_W = 2 * FRAC_W;
    localparam ONE_BIT    = ACC_FRAC_W;

    reg [1:0] state = IDLE;

    always @(posedge clk) begin
        case (state)
            IDLE: begin
                act_done <= 0;
                if (act_start) state <= PROCESS;
            end

            PROCESS: begin
                if (act_in < 0) begin
                    // ReLU Logic: Force negative values to zero
                    act_out <= {D_W{1'b0}};
                end 
                else begin
                    /* * Saturation Logic: Check if upper bits (beyond target INT_W) 
                     * contain any 1s. If so, the value is too large for D_W.
                     */
                    if (|act_in[(2 * D_W) + $clog2(N + 1)-1 : ONE_BIT + (INT_W - 1)]) begin
                        // Cap at maximum positive signed value
                        act_out <= {1'b0, {(D_W-1){1'b1}}};
                    end 
                    else begin
                        /* * Truncation: Slicing the relevant window from the 
                         * expanded accumulation result.
                         */
                        act_out <= act_in[ONE_BIT + (INT_W - 1) -: D_W];
                    end
                end
                state <= FINISH;
            end

            FINISH: begin
                act_done <= 1; // Signal completion to the Neuron ASM
                state    <= IDLE;
            end

            default: state <= IDLE;
        endcase
    end
endmodule