`timescale 1ns / 1ps

// =============================================================================
// Module: hazard_unit
// Project: RV32I RISC-V Processor (Stage 10D)
// Description:
//   Dedicated Hazard Detection Unit for the 5-Stage RV32I Pipelined Processor.
//   Identifies Load-Use data hazards between an uncompleted load instruction
//   in the EX stage (ID/EX) and a dependent instruction in the ID stage (IF/ID).
//
// Load-Use Hazard Condition:
//   A hazard occurs when ALL of the following hold:
//     1. The instruction in EX stage is a Load (ex_mem_read == 1'b1).
//     2. The load destination is nonzero (ex_rd != 5'd0).
//     3. The destination matches a source register genuinely consumed by the
//        instruction currently in the ID stage:
//        - (uses_rs1 && (id_rs1 == ex_rd)) OR
//        - (uses_rs2 && (id_rs2 == ex_rd))
//
// Source Usage Qualification (Prevents False Stalls):
//   - R-type, Store, Branch : use both rs1 and rs2.
//   - I-type, Load, JALR    : use rs1 only (bits [24:20] are immediate, NOT rs2).
//   - LUI, AUIPC, JAL       : use neither rs1 nor rs2.
//
// Stall Actions:
//   When load_use_hazard is asserted:
//     - stall_pc    = 1'b1 : Freeze Program Counter register.
//     - stall_if_id = 1'b1 : Freeze IF/ID pipeline register.
//     - flush_id_ex = 1'b1 : Clear ID/EX control signals (inject NOP bubble).
// =============================================================================

module hazard_unit (
    // Instruction information from ID stage (IF/ID register)
    input  logic [31:0] id_instr,
    input  logic [4:0]  id_rs1,
    input  logic [4:0]  id_rs2,

    // Execution stage control & destination (ID/EX register)
    input  logic        ex_mem_read,
    input  logic [4:0]  ex_rd,

    // Execution stage branch/jump redirect (Stage 10E)
    input  logic        ex_redirect,

    // Pipeline stall and bubble control outputs
    output logic        stall_pc,
    output logic        stall_if_id,
    output logic        flush_id_ex,
    output logic        flush_if_id,
    output logic        load_use_hazard
);

    logic [6:0] id_opcode;
    assign id_opcode = id_instr[6:0];

    // Source Register Usage Flags based on RV32I opcode
    logic uses_rs1;
    logic uses_rs2;

    always_comb begin
        case (id_opcode)
            7'b0110011: begin // R-type: uses rs1, rs2
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
            end
            7'b0010011: begin // I-type arithmetic: uses rs1 only
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b0;
            end
            7'b0000011: begin // Load: uses rs1 only
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b0;
            end
            7'b0100011: begin // Store: uses rs1 (base) and rs2 (data)
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
            end
            7'b1100011: begin // Branch: uses rs1, rs2
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
            end
            7'b1100111: begin // JALR: uses rs1 only
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b0;
            end
            7'b0110111,       // LUI: uses neither
            7'b0010111,       // AUIPC: uses neither
            7'b1101111: begin // JAL: uses neither
                uses_rs1 = 1'b0;
                uses_rs2 = 1'b0;
            end
            default: begin
                uses_rs1 = 1'b0;
                uses_rs2 = 1'b0;
            end
        endcase
    end

    // Raw Load-Use Hazard Detection
    logic raw_load_use;
    always_comb begin
        if (ex_mem_read && (ex_rd != 5'd0) &&
            ((uses_rs1 && (id_rs1 == ex_rd)) ||
             (uses_rs2 && (id_rs2 == ex_rd)))) begin
            raw_load_use = 1'b1;
        end else begin
            raw_load_use = 1'b0;
        end
    end

    // Control-Hazard Priority & Stall/Flush Resolution (Stage 10E):
    // Priority 1: Taken branch / jump redirect in EX (ex_redirect == 1):
    //   - Overrides any younger load-use stall request.
    //   - Flushes both IF/ID and ID/EX (squashing wrong-path instructions).
    //   - Never stalls PC or IF/ID (PC redirects to new target).
    // Priority 2: Load-use hazard (raw_load_use == 1):
    //   - Stalls PC and IF/ID to hold current decode state.
    //   - Injects bubble into ID/EX (flush_id_ex = 1).
    // Priority 3: Normal sequential execution:
    //   - Zero stalls, zero flushes.
    always_comb begin
        if (ex_redirect) begin
            load_use_hazard = 1'b0;
            stall_pc        = 1'b0;
            stall_if_id     = 1'b0;
            flush_id_ex     = 1'b1;
            flush_if_id     = 1'b1;
        end else if (raw_load_use) begin
            load_use_hazard = 1'b1;
            stall_pc        = 1'b1;
            stall_if_id     = 1'b1;
            flush_id_ex     = 1'b1;
            flush_if_id     = 1'b0;
        end else begin
            load_use_hazard = 1'b0;
            stall_pc        = 1'b0;
            stall_if_id     = 1'b0;
            flush_id_ex     = 1'b0;
            flush_if_id     = 1'b0;
        end
    end

endmodule
