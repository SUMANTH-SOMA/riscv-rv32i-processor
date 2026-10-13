`timescale 1ns / 1ps

// =============================================================================
// Module: cpu
// Project: RV32I RISC-V Processor (Stage 8B)
// Description:
//   Single-Cycle RV32I Processor Top-Level Integration.
//   Connects:
//     - Instruction Memory (ROM)
//     - Program Counter Register (PC)
//     - Main Control Unit
//     - Immediate Generator
//     - Architectural Register File (x0-x31)
//     - Secondary ALU Decoder
//     - 32-bit ALU
//     - Data Memory (RAM)
//
// Supported Instruction Subset in Stage 8B:
//   - R-type: ADD, SUB, AND, OR, XOR
//   - I-type Arithmetic: ADDI, ANDI, ORI, XORI
//   - Memory: LW, SW (word-aligned)
//   - Branches: BEQ, BNE
//   - Upper Immediates: LUI, AUIPC
//   - Unconditional Jumps: JAL, JALR
//
// Architectural Invariants:
//   - Rising-edge PC register with deterministic simulation init at 0x00000000.
//   - Register x0 remains strictly hardwired to 0.
//   - JAL and JALR store PC+4 into rd.
//   - JALR clears target address bit 0: (rs1 + imm) & ~1.
//   - AUIPC computes PC + U-immediate.
//   - LUI writes U-immediate directly to rd.
// =============================================================================

module cpu (
    input  logic        clk,        // System Clock
    input  logic        rst_n,      // Active-low synchronous reset
    output logic [31:0] pc_out,     // Current Program Counter (debug/inspection)
    output logic [31:0] instr_out   // Current Instruction Word (debug/inspection)
);

    // -------------------------------------------------------------------------
    // Program Counter Signals
    // -------------------------------------------------------------------------
    logic [31:0] pc;
    logic [31:0] pc_next;
    logic [31:0] pc_plus_4;
    logic [31:0] branch_target;
    logic [31:0] jal_target;
    logic [31:0] jalr_target;

    assign pc_out    = pc;
    assign pc_plus_4 = pc + 32'd4;

    // Simulation initialization for deterministic power-up at PC=0
    initial begin
        pc = 32'h0000_0000;
    end

    // Synchronous Program Counter Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'h0000_0000;
        end else begin
            pc <= pc_next;
        end
    end

    // -------------------------------------------------------------------------
    // Instruction Fetch & Field Extraction
    // -------------------------------------------------------------------------
    logic [31:0] instr;
    assign instr_out = instr;

    instruction_memory #(
        .WORDS(256)
    ) imem (
        .addr(pc),
        .instr(instr)
    );

    logic [6:0] opcode;
    logic [4:0] rd;
    logic [2:0] funct3;
    logic [4:0] rs1;
    logic [4:0] rs2;
    logic       funct7_5;

    assign opcode   = instr[6:0];
    assign rd       = instr[11:7];
    assign funct3   = instr[14:12];
    assign rs1      = instr[19:15];
    assign rs2      = instr[24:20];
    assign funct7_5 = instr[30];

    // -------------------------------------------------------------------------
    // Main Control Unit
    // -------------------------------------------------------------------------
    logic       reg_write;
    logic       mem_read;
    logic       mem_write;
    logic       mem_to_reg;
    logic       alu_src;
    logic       branch;
    logic       jump;
    logic [2:0] imm_src;
    logic [1:0] alu_op;

    control_unit ctrl_unit (
        .opcode(opcode),
        .reg_write(reg_write),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .mem_to_reg(mem_to_reg),
        .alu_src(alu_src),
        .branch(branch),
        .jump(jump),
        .imm_src(imm_src),
        .alu_op(alu_op)
    );

    // -------------------------------------------------------------------------
    // Immediate Generator
    // -------------------------------------------------------------------------
    logic [31:0] imm;

    imm_gen imm_generator (
        .instr(instr),
        .imm_src(imm_src),
        .imm(imm)
    );

    // -------------------------------------------------------------------------
    // Architectural Register File
    // -------------------------------------------------------------------------
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [31:0] writeback_data;

    register_file reg_file (
        .clk(clk),
        .we(reg_write),
        .raddr1(rs1),
        .raddr2(rs2),
        .waddr(rd),
        .wdata(writeback_data),
        .rdata1(rs1_data),
        .rdata2(rs2_data)
    );

    // -------------------------------------------------------------------------
    // ALU Decoder & Arithmetic Logic Unit
    // -------------------------------------------------------------------------
    logic [3:0]  alu_control;
    logic [31:0] alu_operand_a;
    logic [31:0] alu_operand_b;
    logic [31:0] alu_result;
    logic        alu_zero;

    alu_decoder alu_dec (
        .alu_op(alu_op),
        .funct3(funct3),
        .funct7_5(funct7_5),
        .alu_control(alu_control)
    );

    // Operand A: PC for AUIPC (opcode 0010111), otherwise rs1_data
    assign alu_operand_a = (opcode == 7'b0010111) ? pc : rs1_data;

    // Operand B: Immediate if alu_src asserted, otherwise rs2_data
    assign alu_operand_b = (alu_src) ? imm : rs2_data;

    alu core_alu (
        .a(alu_operand_a),
        .b(alu_operand_b),
        .alu_op(alu_control),
        .alu_result(alu_result),
        .zero(alu_zero)
    );

    // -------------------------------------------------------------------------
    // Data Memory
    // -------------------------------------------------------------------------
    logic [31:0] mem_read_data;

    data_memory #(
        .WORDS(256)
    ) dmem (
        .clk(clk),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .addr(alu_result),
        .write_data(rs2_data),
        .read_data(mem_read_data)
    );

    // -------------------------------------------------------------------------
    // Writeback Multiplexer
    // -------------------------------------------------------------------------
    // Priority order:
    //   1. Memory load data (mem_to_reg)
    //   2. Link address PC+4 for JAL / JALR (jump)
    //   3. Raw U-immediate for LUI (opcode == 0110111)
    //   4. Default ALU result (R-type, I-type arith, AUIPC)
    always_comb begin
        if (mem_to_reg) begin
            writeback_data = mem_read_data;
        end else if (jump) begin
            writeback_data = pc_plus_4;
        end else if (opcode == 7'b0110111) begin
            writeback_data = imm;
        end else begin
            writeback_data = alu_result;
        end
    end

    // -------------------------------------------------------------------------
    // Branch & Jump Control Flow Logic
    // -------------------------------------------------------------------------
    logic branch_taken;

    always_comb begin
        if (branch) begin
            case (funct3)
                3'b000:  branch_taken = alu_zero;                           // BEQ: equal
                3'b001:  branch_taken = ~alu_zero;                          // BNE: not equal
                3'b100:  branch_taken = ($signed(rs1_data) < $signed(rs2_data));  // BLT: signed less-than
                3'b101:  branch_taken = ($signed(rs1_data) >= $signed(rs2_data)); // BGE: signed greater-or-equal
                3'b110:  branch_taken = (rs1_data < rs2_data);              // BLTU: unsigned less-than
                3'b111:  branch_taken = (rs1_data >= rs2_data);             // BGEU: unsigned greater-or-equal
                default: branch_taken = 1'b0;                               // Unsupported branch funct3 safe 0
            endcase
        end else begin
            branch_taken = 1'b0;
        end
    end

    assign branch_target = pc + imm;
    assign jal_target    = pc + imm;
    assign jalr_target   = (rs1_data + imm) & ~32'h0000_0001; // Bit 0 forced to 0

    // Next PC Selection
    always_comb begin
        if (opcode == 7'b1100111) begin
            // JALR: Jump to register-relative address
            pc_next = jalr_target;
        end else if (opcode == 7'b1101111) begin
            // JAL: Jump to PC-relative offset
            pc_next = jal_target;
        end else if (branch_taken) begin
            // Taken branch
            pc_next = branch_target;
        end else begin
            // Sequential execution
            pc_next = pc_plus_4;
        end
    end

endmodule
