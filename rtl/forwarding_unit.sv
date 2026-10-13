`timescale 1ns / 1ps

// =============================================================================
// Module: forwarding_unit
// Project: RV32I RISC-V Processor (Stage 10C)
// Description:
//   Data Forwarding (Bypass) Unit for the 5-Stage RV32I Pipelined Processor.
//   Detects Read-After-Write (RAW) data hazards for EX-stage operands and
//   generates forward selection controls:
//     - forward_a : Controls ALU Operand A / rs1 forwarding
//     - forward_b : Controls ALU Operand B / rs2 / store-data forwarding
//
// Forwarding Path Priority:
//   1. EX/MEM -> EX (Distance 1 hazard): Highest Priority
//      Forwards computed ALU result, LUI immediate, or PC+4 from the
//      immediately preceding instruction currently in EX/MEM.
//      * EXCEPTION: If the EX/MEM instruction is a LOAD (mem_to_reg == 1),
//        data is not yet available in EX/MEM. This unit does NOT forward
//        an unread load's effective address (load-use stall handled in Stage 10D).
//   2. MEM/WB -> EX (Distance 2 hazard):
//      Forwards committed writeback data (including loaded data from memory,
//      ALU results, LUI, or PC+4) from the instruction in MEM/WB.
//   3. No Forwarding (2'b00):
//      Uses operand read from the register file during ID stage.
//
// Hardwired Invariant:
//   Register x0 (5'd0) is never forwarded (remains strictly zero).
// =============================================================================

module forwarding_unit (
    // Source registers from ID/EX register (EX stage)
    input  logic [4:0] ex_rs1,
    input  logic [4:0] ex_rs2,

    // Destination and control from EX/MEM register (MEM stage)
    input  logic       mem_reg_write,
    input  logic       mem_mem_to_reg,  // Load indicator: 1 if instruction is a load
    input  logic [4:0] mem_rd,

    // Destination and control from MEM/WB register (WB stage)
    input  logic       wb_reg_write,
    input  logic [4:0] wb_rd,

    // Forwarding control outputs to EX stage muxes
    // 2'b00: Use ID/EX register operand
    // 2'b10: Forward from EX/MEM stage
    // 2'b01: Forward from MEM/WB stage
    output logic [1:0] forward_a,
    output logic [1:0] forward_b
);

    // -------------------------------------------------------------------------
    // Forwarding Logic for Operand A (rs1)
    // -------------------------------------------------------------------------
    always_comb begin
        // EX/MEM Hazard (Priority 1):
        // Active when instruction in EX/MEM writes to rd, rd is not x0,
        // rd matches ex_rs1, and instruction is NOT an uncompleted load.
        if (mem_reg_write && (mem_rd != 5'd0) && !mem_mem_to_reg && (mem_rd == ex_rs1)) begin
            forward_a = 2'b10;
        // MEM/WB Hazard (Priority 2):
        // Active when instruction in MEM/WB writes to rd, rd is not x0,
        // and rd matches ex_rs1.
        end else if (wb_reg_write && (wb_rd != 5'd0) && (wb_rd == ex_rs1)) begin
            forward_a = 2'b01;
        // Default: No hazard, use ID/EX register value
        end else begin
            forward_a = 2'b00;
        end
    end

    // -------------------------------------------------------------------------
    // Forwarding Logic for Operand B (rs2)
    // -------------------------------------------------------------------------
    always_comb begin
        // EX/MEM Hazard (Priority 1):
        // Active when instruction in EX/MEM writes to rd, rd is not x0,
        // rd matches ex_rs2, and instruction is NOT an uncompleted load.
        if (mem_reg_write && (mem_rd != 5'd0) && !mem_mem_to_reg && (mem_rd == ex_rs2)) begin
            forward_b = 2'b10;
        // MEM/WB Hazard (Priority 2):
        // Active when instruction in MEM/WB writes to rd, rd is not x0,
        // and rd matches ex_rs2.
        end else if (wb_reg_write && (wb_rd != 5'd0) && (wb_rd == ex_rs2)) begin
            forward_b = 2'b01;
        // Default: No hazard, use ID/EX register value
        end else begin
            forward_b = 2'b00;
        end
    end

endmodule
