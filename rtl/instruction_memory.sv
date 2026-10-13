`timescale 1ns / 1ps

// =============================================================================
// Module: instruction_memory
// Project: RV32I RISC-V Processor (Stage 6)
// Description:
//   Simulation-oriented asynchronous read-only Instruction Memory (ROM).
//   - Parameterized word capacity (default 256 words = 1024 bytes).
//   - Byte-addressed input (addr[31:0]); instructions are 32 bits (4 bytes).
//   - Word indexing performed via addr[31:2].
//   - Unaligned Address Policy:
//       Non-word-aligned addresses (where addr[1:0] != 2'b00) are truncated
//       to the containing word boundary (addr[31:2]).
//   - Out-of-Range Policy:
//       Addresses indexing beyond the allocated word capacity (addr[31:2] >= WORDS)
//       return a safe RV32I NOP instruction (32'h0000_0013: addi x0, x0, 0).
//   - Initialization:
//       All memory words are initialized to NOP (32'h0000_0013) for deterministic
//       simulation bringup.
//
// NOTE: This module is intended specifically for functional simulation.
// It does not implement physical bus protocols (e.g. AXI/AHB/Wishbone), wait-states,
// or hardware cache structures.
// =============================================================================

module instruction_memory #(
    parameter int WORDS = 256 // Number of 32-bit instruction words
) (
    input  logic [31:0] addr,  // 32-bit byte address from Program Counter
    output logic [31:0] instr  // 32-bit fetched instruction word
);

    // RV32I Architecture Canonical NOP: addi x0, x0, 0
    localparam logic [31:0] NOP_INSTR = 32'h0000_0013;

    // Internal memory array of 32-bit words
    logic [31:0] mem [0:WORDS-1];

    // Simulation initialization: fill entire memory with NOPs
    initial begin
        for (int i = 0; i < WORDS; i++) begin
            mem[i] = NOP_INSTR;
        end
    end

    // Combinational instruction fetch with bounds checking and word alignment
    always_comb begin
        if (addr[31:2] < WORDS) begin
            // Address is within range: return indexed instruction word
            instr = mem[addr[31:2]];
        end else begin
            // Address is out of range: return safe NOP
            instr = NOP_INSTR;
        end
    end

endmodule
