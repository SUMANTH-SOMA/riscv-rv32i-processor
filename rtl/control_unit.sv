`timescale 1ns / 1ps

// =============================================================================
// Module: control_unit
// Project: RV32I RISC-V Processor (Stage 5)
// Description:
//   Main combinatorial Control Unit for RV32I instruction classes.
//   Decodes the 7-bit instruction opcode and generates all top-level datapath
//   control signals, immediate format selectors, and high-level ALU operation modes.
//
// Supported Opcode Classes:
//   - 7'b0110011 : R-type register arithmetic (ADD, SUB, AND, OR, XOR, etc.)
//   - 7'b0010011 : I-type immediate arithmetic (ADDI, ANDI, ORI, XORI, etc.)
//   - 7'b0000011 : Load instructions (LW, LH, LB, etc.)
//   - 7'b0100011 : Store instructions (SW, SH, SB)
//   - 7'b1100011 : Conditional branch instructions (BEQ, BNE, BLT, BGE, etc.)
//   - 7'b0110111 : LUI (Load Upper Immediate)
//   - 7'b0010111 : AUIPC (Add Upper Immediate to PC)
//   - 7'b1101111 : JAL (Jump and Link)
//   - 7'b1100111 : JALR (Jump and Link Register)
//
// ALU Operation Class Mapping (alu_op [1:0]):
//   2'b00 (ALU_OP_ADD)  : Force ADD operation. Used for memory effective address
//                         generation (Loads, Stores) and PC-relative / immediate
//                         arithmetic (AUIPC, LUI, JAL, JALR).
//   2'b01 (ALU_OP_SUB)  : Force SUB / compare operation for branch decision evaluation.
//   2'b10 (ALU_OP_RTYPE): R-type instruction class. Indicates to secondary ALU decoder
//                         to decode {funct7[5], funct3} into 4-bit ALU control.
//   2'b11 (ALU_OP_ITYPE): I-type instruction class. Indicates to secondary ALU decoder
//                         to decode funct3 (immediate arithmetic).
//
// Immediate Format Selectors (imm_src [2:0]):
//   3'b000 = I-type | 3'b001 = S-type | 3'b010 = B-type
//   3'b011 = U-type | 3'b100 = J-type
//
// Unsupported Opcodes:
//   Drive all control outputs to safe defaults (0).
// =============================================================================

module control_unit (
    input  logic [6:0] opcode,      // 7-bit instruction opcode (instr[6:0])
    output logic       reg_write,   // Register file write enable
    output logic       mem_read,    // Data memory read enable
    output logic       mem_write,   // Data memory write enable
    output logic       mem_to_reg,  // Write-back source mux: 0=ALU result, 1=Mem data
    output logic       alu_src,     // ALU operand B mux: 0=rs2 data, 1=immediate
    output logic       branch,      // Conditional branch indicator
    output logic       jump,        // Unconditional jump indicator (JAL, JALR)
    output logic [2:0] imm_src,     // Immediate generator format selector
    output logic [1:0] alu_op       // High-level ALU operation class
);

    // Opcode Constant Definitions
    localparam logic [6:0] OPC_R_TYPE = 7'b0110011;
    localparam logic [6:0] OPC_I_TYPE = 7'b0010011;
    localparam logic [6:0] OPC_LOAD   = 7'b0000011;
    localparam logic [6:0] OPC_STORE  = 7'b0100011;
    localparam logic [6:0] OPC_BRANCH = 7'b1100011;
    localparam logic [6:0] OPC_LUI    = 7'b0110111;
    localparam logic [6:0] OPC_AUIPC  = 7'b0010111;
    localparam logic [6:0] OPC_JAL    = 7'b1101111;
    localparam logic [6:0] OPC_JALR   = 7'b1100111;

    // Immediate Format Selectors
    localparam logic [2:0] IMM_I = 3'b000;
    localparam logic [2:0] IMM_S = 3'b001;
    localparam logic [2:0] IMM_B = 3'b010;
    localparam logic [2:0] IMM_U = 3'b011;
    localparam logic [2:0] IMM_J = 3'b100;

    // ALU Operation Class Constants
    localparam logic [1:0] ALU_OP_ADD   = 2'b00;
    localparam logic [1:0] ALU_OP_SUB   = 2'b01;
    localparam logic [1:0] ALU_OP_RTYPE = 2'b10;
    localparam logic [1:0] ALU_OP_ITYPE = 2'b11;

    // Combinational instruction decode logic
    always_comb begin
        case (opcode)
            // R-type: Register-Register arithmetic (rd <= rs1 op rs2)
            OPC_R_TYPE: begin
                reg_write  = 1'b1;
                mem_read   = 1'b0;
                mem_write  = 1'b0;
                mem_to_reg = 1'b0;
                alu_src    = 1'b0;
                branch     = 1'b0;
                jump       = 1'b0;
                imm_src    = IMM_I; // Don't care, default safe
                alu_op     = ALU_OP_RTYPE;
            end

            // I-type arithmetic: Register-Immediate arithmetic (rd <= rs1 op imm)
            OPC_I_TYPE: begin
                reg_write  = 1'b1;
                mem_read   = 1'b0;
                mem_write  = 1'b0;
                mem_to_reg = 1'b0;
                alu_src    = 1'b1;
                branch     = 1'b0;
                jump       = 1'b0;
                imm_src    = IMM_I;
                alu_op     = ALU_OP_ITYPE;
            end

            // Load: Memory read into register (rd <= Mem[rs1 + imm])
            OPC_LOAD: begin
                reg_write  = 1'b1;
                mem_read   = 1'b1;
                mem_write  = 1'b0;
                mem_to_reg = 1'b1;
                alu_src    = 1'b1;
                branch     = 1'b0;
                jump       = 1'b0;
                imm_src    = IMM_I;
                alu_op     = ALU_OP_ADD;
            end

            // Store: Register write to memory (Mem[rs1 + imm] <= rs2)
            OPC_STORE: begin
                reg_write  = 1'b0;
                mem_read   = 1'b0;
                mem_write  = 1'b1;
                mem_to_reg = 1'b0;
                alu_src    = 1'b1;
                branch     = 1'b0;
                jump       = 1'b0;
                imm_src    = IMM_S;
                alu_op     = ALU_OP_ADD;
            end

            // Branch: Conditional branch (if rs1 cond rs2, PC <= PC + imm)
            OPC_BRANCH: begin
                reg_write  = 1'b0;
                mem_read   = 1'b0;
                mem_write  = 1'b0;
                mem_to_reg = 1'b0;
                alu_src    = 1'b0;
                branch     = 1'b1;
                jump       = 1'b0;
                imm_src    = IMM_B;
                alu_op     = ALU_OP_SUB;
            end

            // LUI: Load Upper Immediate (rd <= imm << 12)
            OPC_LUI: begin
                reg_write  = 1'b1;
                mem_read   = 1'b0;
                mem_write  = 1'b0;
                mem_to_reg = 1'b0;
                alu_src    = 1'b1;
                branch     = 1'b0;
                jump       = 1'b0;
                imm_src    = IMM_U;
                alu_op     = ALU_OP_ADD;
            end

            // AUIPC: Add Upper Immediate to PC (rd <= PC + (imm << 12))
            OPC_AUIPC: begin
                reg_write  = 1'b1;
                mem_read   = 1'b0;
                mem_write  = 1'b0;
                mem_to_reg = 1'b0;
                alu_src    = 1'b1;
                branch     = 1'b0;
                jump       = 1'b0;
                imm_src    = IMM_U;
                alu_op     = ALU_OP_ADD;
            end

            // JAL: Jump and Link (rd <= PC + 4, PC <= PC + imm)
            OPC_JAL: begin
                reg_write  = 1'b1;
                mem_read   = 1'b0;
                mem_write  = 1'b0;
                mem_to_reg = 1'b0;
                alu_src    = 1'b0;
                branch     = 1'b0;
                jump       = 1'b1;
                imm_src    = IMM_J;
                alu_op     = ALU_OP_ADD;
            end

            // JALR: Jump and Link Register (rd <= PC + 4, PC <= rs1 + imm)
            OPC_JALR: begin
                reg_write  = 1'b1;
                mem_read   = 1'b0;
                mem_write  = 1'b0;
                mem_to_reg = 1'b0;
                alu_src    = 1'b1;
                branch     = 1'b0;
                jump       = 1'b1;
                imm_src    = IMM_I;
                alu_op     = ALU_OP_ADD;
            end

            // Default / Unsupported opcodes: Safe all-zero defaults
            default: begin
                reg_write  = 1'b0;
                mem_read   = 1'b0;
                mem_write  = 1'b0;
                mem_to_reg = 1'b0;
                alu_src    = 1'b0;
                branch     = 1'b0;
                jump       = 1'b0;
                imm_src    = 3'b000;
                alu_op     = 2'b00;
            end
        endcase
    end

endmodule
