`timescale 1ns / 1ps

/* * REMARK: This module acts as a specialized Read-Only Memory (ROM) for neural 
 * weights. It is designed for high-throughput parallel processing, allowing 
 * the system to fetch 'P' weights in a single read operation. When 'ren' is 
 * asserted, the module packages a contiguous block of weights starting from 
 * 'start_add' into a single wide output string.
 *
 * EXTERNAL FILES: The module initializes its internal memory using the 
 * 'weightFile' parameter (binary format). Ensure the text file contains 
 * exactly 'N' entries of bit-width 'D_W' to match the memory dimensions.
 */

module Weight_ROM_mod #(
    parameter weightFile = "weights.txt", 
    parameter N = 4,              // Total number of weights in memory
    parameter P = 2,              // Number of weights to fetch in parallel
    parameter D_W = 16,           // Data width per weight
    parameter A_W = $clog2(N)     // Address width
)(
    input                  clk,
    input                  ren,           // Read Enable
    input      [A_W-1:0]   start_add,     // Starting index for the fetch
    output reg signed [P*D_W-1:0] weight_string, // Concatenated output of P weights
    output reg             weight_valid   // High when weight_string is ready
);

    // --- State Machine Definitions ---
    localparam IDLE = 0, READ = 1, DONE = 2;
    reg [1:0] state, next_state;

    // --- Memory Array Initialization ---
    reg signed [D_W-1:0] mem [0:N-1];
    initial $readmemb(weightFile, mem);

    // --- State Transition Logic ---
    initial state = IDLE;
    always @(posedge clk) begin
        state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE: if (ren) next_state = READ;
            READ: next_state = DONE;  // Memory access cycle
            DONE: next_state = IDLE;  // Reset for next handshake
            default: next_state = IDLE;
        endcase
    end

    // --- Output Control Logic ---
    always @(posedge clk) begin
        case (state)
            IDLE: weight_valid <= 1'b0;
            DONE: weight_valid <= 1'b1; // Valid for one cycle after READ
        endcase
    end
  
    // --- Parallel Data Packing Logic ---
    genvar j;
    generate
        for (j = 0; j < P; j = j + 1) begin : PACK_WEIGHT
            always @(posedge clk) begin
                if (state == READ) begin
                    /* * Implementation Note: To maintain {mem[0], mem[1]} order,
                     * j=0 is placed at the most significant chunk of the string.
                     * Boundary Guard: If (start_add + j) exceeds N, pads with 0.
                     */
                    if ((start_add + j) < N) begin
                        weight_string[(P-1-j)*D_W +: D_W] <= $signed(mem[start_add + j]);
                    end
                    else begin
                        weight_string[(P-1-j)*D_W +: D_W] <= {D_W{1'b0}};
                    end
                end
            end
        end
    endgenerate

endmodule