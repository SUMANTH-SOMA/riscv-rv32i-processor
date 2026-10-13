`timescale 1ns / 1ps

// =============================================================================
// Module: data_memory
// Project: RV32I RISC-V Processor (Stage 7)
// Description:
//   Simulation-oriented 32-bit Data Memory (RAM).
//   - Parameterized word capacity (default 256 words = 1024 bytes).
//   - Byte-addressed input (addr[31:0]); word indexing via addr[31:2].
//   - Synchronous writes on posedge clk when mem_write is asserted.
//   - Combinational reads when mem_read is asserted; outputs zero when mem_read is low.
//
// Alignment Policy:
//   Word alignment is strictly enforced. Unaligned accesses (addr[1:0] != 2'b00)
//   are rejected:
//     * Unaligned reads return 32'h0000_0000.
//     * Unaligned writes are ignored (no memory mutation).
//
// Out-of-Range Policy:
//   Addresses indexing beyond the allocated word capacity (addr[31:2] >= WORDS):
//     * Out-of-range reads return 32'h0000_0000.
//     * Out-of-range writes are ignored.
//
// Simultaneous Read/Write Behavior:
//   Reads are combinational while writes are synchronous. During a cycle where
//   both mem_read and mem_write are asserted for the same address:
//     * Prior to posedge clk: read_data presents the pre-existing (old) word.
//     * At/after posedge clk: memory updates to write_data, and read_data
//       combinatorially updates to reflect the newly written data.
//
// NOTE: Memory array is initialized to 0 for deterministic simulation.
// This is a simulation convenience and does NOT model ASIC power-on state.
// =============================================================================

module data_memory #(
    parameter int WORDS = 256 // Number of 32-bit words (default 256 words = 1KB)
) (
    input  logic        clk,        // Positive-edge clock
    input  logic        mem_read,   // Read enable (active high)
    input  logic        mem_write,  // Synchronous write enable (active high)
    input  logic [31:0] addr,       // 32-bit byte address
    input  logic [31:0] write_data, // 32-bit data to write
    output logic [31:0] read_data   // 32-bit combinational read output
);

    // 32-bit internal memory array
    logic [31:0] mem [0:WORDS-1];

    // Address validation helper flags
    logic is_aligned;
    logic is_in_range;

    assign is_aligned  = (addr[1:0] == 2'b00);
    assign is_in_range = (addr[31:2] < WORDS);

    // -------------------------------------------------------------------------
    // Simulation Initialization:
    // Zero-initialize memory array for deterministic bringup.
    // -------------------------------------------------------------------------
    initial begin
        for (int i = 0; i < WORDS; i++) begin
            mem[i] = 32'h0000_0000;
        end
    end

    // -------------------------------------------------------------------------
    // Synchronous Write Port:
    // Writes occur on posedge clk if mem_write is active and access is valid.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (mem_write && is_aligned && is_in_range) begin
            mem[addr[31:2]] <= write_data;
        end
    end

    // -------------------------------------------------------------------------
    // Combinational Read Port:
    // Read data is output combinationally when mem_read is active and access
    // is aligned and in-range. Otherwise, 32'h0000_0000 is output.
    // -------------------------------------------------------------------------
    always_comb begin
        if (mem_read && is_aligned && is_in_range) begin
            read_data = mem[addr[31:2]];
        end else begin
            read_data = 32'h0000_0000;
        end
    end

endmodule
