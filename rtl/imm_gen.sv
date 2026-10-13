`timescale 1ns / 1ps

// =============================================================================
// Module: imm_gen
// Project: RV32I RISC-V Processor (Stage 4)
// Description:
//   Combinational Immediate Generator for RV32I ISA.
//   Reconstructs and sign-extends (or zero-pads) immediate values from the
//   raw 32-bit instruction word based on the format selector (imm_src).
//
// Immediate Formats and Selector Mapping (imm_src [2:0]):
//   3'b000 (IMM_I): I-type immediate (ADDI, LW, JALR, etc.)
//                   imm[31:0] = {{20{instr[31]}}, instr[31:20]}
//   3'b001 (IMM_S): S-type immediate (SW, SH, SB)
//                   imm[31:0] = {{20{instr[31]}}, instr[31:25], instr[11:7]}
//   3'b010 (IMM_B): B-type immediate (BEQ, BNE, BLT, etc.)
//                   Reconstructed 13-bit offset:
//                   {instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}
//                   Sign-extended to 32 bits (bit 0 is forced zero).
//   3'b011 (IMM_U): U-type immediate (LUI, AUIPC)
//                   imm[31:0] = {instr[31:12], 12'b0} (lowest 12 bits zero).
//   3'b100 (IMM_J): J-type immediate (JAL)
//                   Reconstructed 21-bit offset:
//                   {instr[31], instr[19:12], instr[20], instr[30:21], 1'b0}
//                   Sign-extended to 32 bits (bit 0 is forced zero).
//   Others        : Outputs 32'h0000_0000.
// =============================================================================

module imm_gen (
    input  logic [31:0] instr,   // 32-bit RISC-V instruction word
    input  logic [2:0]  imm_src, // 3-bit immediate format selector
    output logic [31:0] imm      // 32-bit reconstructed immediate
);

    // Immediate Format Selectors
    localparam logic [2:0] IMM_I = 3'b000;
    localparam logic [2:0] IMM_S = 3'b001;
    localparam logic [2:0] IMM_B = 3'b010;
    localparam logic [2:0] IMM_U = 3'b011;
    localparam logic [2:0] IMM_J = 3'b100;

    // Combinational immediate reconstruction and extension
    always_comb begin
        case (imm_src)
            // I-type: 12-bit immediate from instr[31:20], sign-extended to 32 bits
            IMM_I: begin
                imm = {{20{instr[31]}}, instr[31:20]};
            end

            // S-type: 12-bit immediate from {instr[31:25], instr[11:7]}, sign-extended to 32 bits
            IMM_S: begin
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            end

            // B-type: 13-bit branch offset from {instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}
            // Sign-extended by 19 bits; bit 0 forced to 0 for halfword-aligned branch targets.
            IMM_B: begin
                imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            end

            // U-type: Upper 20-bit immediate from instr[31:12], lowest 12 bits zeroed
            IMM_U: begin
                imm = {instr[31:12], 12'b0};
            end

            // J-type: 21-bit jump offset from {instr[31], instr[19:12], instr[20], instr[30:21], 1'b0}
            // Sign-extended by 11 bits; bit 0 forced to 0 for halfword-aligned jump targets.
            IMM_J: begin
                imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            end

            // Unmapped selectors default to zero
            default: begin
                imm = 32'h0000_0000;
            end
        endcase
    end

endmodule
