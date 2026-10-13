`timescale 1ns / 1ps

// =============================================================================
// Module: alu_decoder
// Project: RV32I RISC-V Processor (Stage 9B Extension)
// Description:
//   Secondary combinational ALU decoder for RV32I.
//   Translates the 2-bit instruction class control signal (alu_op) and the
//   instruction's funct3 / funct7[5] fields into the 4-bit ALU operation
//   selector (alu_control) used by rtl/alu.sv.
//
// ALU Operation Selector Encodings (matching rtl/alu.sv):
//   4'b0000 (ALU_ADD) : a + b
//   4'b1000 (ALU_SUB) : a - b
//   4'b0001 (ALU_SLL) : a << b[4:0]
//   4'b0010 (ALU_SLT) : ($signed(a) < $signed(b)) ? 1 : 0
//   4'b0011 (ALU_SLTU): (a < b) ? 1 : 0
//   4'b0100 (ALU_XOR) : a ^ b
//   4'b0101 (ALU_SRL) : a >> b[4:0]
//   4'b1101 (ALU_SRA) : $signed(a) >>> b[4:0]
//   4'b0110 (ALU_OR)  : a | b
//   4'b0111 (ALU_AND) : a & b
//
// Decoding Rules:
//   - alu_op == 2'b00: Force ADD (Loads, Stores, AUIPC, LUI, JAL, JALR)
//   - alu_op == 2'b01: Force SUB (Branch equality/difference evaluation)
//   - alu_op == 2'b10: R-type instructions (differentiates ADD/SUB, SRL/SRA via funct7_5)
//   - alu_op == 2'b11: I-type arithmetic instructions (differentiates SRLI/SRAI via funct7_5;
//                      ADDI is never treated as SUB)
//   - Default: Safe deterministic default to ALU_ADD (4'b0000)
// =============================================================================

module alu_decoder (
    input  logic [1:0] alu_op,      // 2-bit class control signal from control_unit
    input  logic [2:0] funct3,      // 3-bit function code (instr[14:12])
    input  logic       funct7_5,    // Bit 30 of instruction (funct7[5])
    output logic [3:0] alu_control  // 4-bit control code to rtl/alu.sv
);

    // ALU Control Constants matching rtl/alu.sv
    localparam logic [3:0] ALU_ADD  = 4'b0000;
    localparam logic [3:0] ALU_SUB  = 4'b1000;
    localparam logic [3:0] ALU_SLL  = 4'b0001;
    localparam logic [3:0] ALU_SLT  = 4'b0010;
    localparam logic [3:0] ALU_SLTU = 4'b0011;
    localparam logic [3:0] ALU_XOR  = 4'b0100;
    localparam logic [3:0] ALU_SRL  = 4'b0101;
    localparam logic [3:0] ALU_SRA  = 4'b1101;
    localparam logic [3:0] ALU_OR   = 4'b0110;
    localparam logic [3:0] ALU_AND  = 4'b0111;

    always_comb begin
        case (alu_op)
            // 2'b00: Address calculation & direct additions (LW, SW, AUIPC, LUI, JAL, JALR)
            2'b00: begin
                alu_control = ALU_ADD;
            end

            // 2'b01: Branch comparisons
            2'b01: begin
                alu_control = ALU_SUB;
            end

            // 2'b10: R-type register-register arithmetic
            2'b10: begin
                case (funct3)
                    3'b000:  alu_control = (funct7_5) ? ALU_SUB : ALU_ADD;
                    3'b001:  alu_control = ALU_SLL;
                    3'b010:  alu_control = ALU_SLT;
                    3'b011:  alu_control = ALU_SLTU;
                    3'b100:  alu_control = ALU_XOR;
                    3'b101:  alu_control = (funct7_5) ? ALU_SRA : ALU_SRL;
                    3'b110:  alu_control = ALU_OR;
                    3'b111:  alu_control = ALU_AND;
                    default: alu_control = ALU_ADD;
                endcase
            end

            // 2'b11: I-type register-immediate arithmetic
            2'b11: begin
                case (funct3)
                    3'b000:  alu_control = ALU_ADD; // ADDI (never SUB)
                    3'b001:  alu_control = ALU_SLL; // SLLI
                    3'b010:  alu_control = ALU_SLT; // SLTI
                    3'b011:  alu_control = ALU_SLTU;// SLTIU
                    3'b100:  alu_control = ALU_XOR; // XORI
                    3'b101:  alu_control = (funct7_5) ? ALU_SRA : ALU_SRL; // SRLI vs SRAI
                    3'b110:  alu_control = ALU_OR;  // ORI
                    3'b111:  alu_control = ALU_AND; // ANDI
                    default: alu_control = ALU_ADD;
                endcase
            end

            default: begin
                alu_control = ALU_ADD;
            end
        endcase
    end

endmodule
