`timescale 1ns / 1ps

// =============================================================================
// Module: alu
// Project: RV32I RISC-V Processor (Stage 9B Extension)
// Description:
//   32-bit combinational Arithmetic Logic Unit (ALU).
//   Computes arithmetic, logical, shift, and comparison operations for 32-bit operands.
//
// Operation Selector Encoding (alu_op [3:0]):
//   4'b0000 (ALU_ADD) : alu_result = a + b
//   4'b1000 (ALU_SUB) : alu_result = a - b
//   4'b0001 (ALU_SLL) : alu_result = a << b[4:0] (Logical shift left)
//   4'b0010 (ALU_SLT) : alu_result = ($signed(a) < $signed(b)) ? 1 : 0 (Signed compare)
//   4'b0011 (ALU_SLTU): alu_result = (a < b) ? 1 : 0 (Unsigned compare)
//   4'b0100 (ALU_XOR) : alu_result = a ^ b
//   4'b0101 (ALU_SRL) : alu_result = a >> b[4:0] (Logical shift right)
//   4'b1101 (ALU_SRA) : alu_result = $signed(a) >>> b[4:0] (Arithmetic shift right, sign-extended)
//   4'b0110 (ALU_OR)  : alu_result = a | b
//   4'b0111 (ALU_AND) : alu_result = a & b
//
// Shift and Comparison Semantics:
//   - Shift operations only use the 5 least-significant bits of operand B (b[4:0]).
//   - SRA treats operand A as signed ($signed(a)) so the MSB sign bit is replicated.
//   - SLT treats operands A and B as signed two's complement values.
//   - SLTU treats operands A and B as unsigned values.
// =============================================================================

module alu (
    input  logic [31:0] a,          // 32-bit input operand A
    input  logic [31:0] b,          // 32-bit input operand B
    input  logic [3:0]  alu_op,     // 4-bit operation selector
    output logic [31:0] alu_result, // 32-bit computed result
    output logic        zero        // Active-high zero flag (1 when alu_result == 0)
);

    // ALU Operation Selector Constants
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

    // Combinational evaluation of the selected operation
    always_comb begin
        case (alu_op)
            ALU_ADD:  alu_result = a + b;
            ALU_SUB:  alu_result = a - b;
            ALU_SLL:  alu_result = a << b[4:0];
            ALU_SLT:  alu_result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            ALU_SLTU: alu_result = (a < b) ? 32'd1 : 32'd0;
            ALU_XOR:  alu_result = a ^ b;
            ALU_SRL:  alu_result = a >> b[4:0];
            ALU_SRA:  alu_result = $signed(a) >>> b[4:0];
            ALU_OR:   alu_result = a | b;
            ALU_AND:  alu_result = a & b;
            default:  alu_result = 32'h0000_0000;
        endcase
    end

    // Zero flag output: asserted when alu_result equals zero
    assign zero = (alu_result == 32'h0000_0000);

endmodule
