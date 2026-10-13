`timescale 1ns / 1ps

// =============================================================================
// Module: cpu_pipeline
// Project: RV32I RISC-V Processor (Stage 10B)
// Description:
//   Minimal Five-Stage Pipelined RV32I Processor Top-Level Integration.
//   Pipeline Organization:
//     IF  (Instruction Fetch)
//     ID  (Instruction Decode & Register Fetch)
//     EX  (Execute & Address Calculation)
//     MEM (Memory Access)
//     WB  (Register Writeback)
//
// Key Architectural Invariants for Stage 10B:
//   - Strict sequential flow (PC increments by 4).
//   - Pipeline registers propagate state across clock boundaries.
//   - Hardware preserves memory access metadata (mem_to_reg, mem_read) across
//     EX/MEM and MEM/WB stages for future forwarding and load-use disambiguation.
//   - Internal register-file write-through bypass in ID stage handles WB->ID
//     dependencies without stalls.
//   - Zero speculative execution, zero hazard stalls, zero forwarding (by design
//     for Stage 10B foundation; instructions must be independent or NOP-padded).
//
// Reused Modules (Interfaces Preserved):
//   - rtl/instruction_memory.sv
//   - rtl/control_unit.sv
//   - rtl/imm_gen.sv
//   - rtl/register_file.sv
//   - rtl/alu_decoder.sv
//   - rtl/alu.sv
//   - rtl/data_memory.sv
// =============================================================================

module cpu_pipeline (
    input  logic        clk,        // System Clock
    input  logic        rst_n,      // Active-low synchronous reset
    output logic [31:0] pc_out,     // Current IF stage PC (debug probe)
    output logic [31:0] instr_out   // Current IF stage instruction (debug probe)
);

    // =========================================================================
    // Hazard Detection Signals & Control Flow Redirection (Stage 10E)
    // =========================================================================
    logic stall_pc;
    logic stall_if_id;
    logic flush_id_ex;
    logic flush_if_id;
    logic load_use_hazard;
    logic ex_redirect;
    logic [31:0] ex_redirect_target;

    // =========================================================================
    // STAGE 1: INSTRUCTION FETCH (IF)
    // =========================================================================
    logic [31:0] if_pc;
    logic [31:0] if_pc_next;
    logic [31:0] if_pc_plus_4;
    logic [31:0] if_instr;

    assign pc_out    = if_pc;
    assign instr_out = if_instr;

    assign if_pc_plus_4 = if_pc + 32'd4;
    assign if_pc_next   = (ex_redirect) ? ex_redirect_target : if_pc_plus_4;

    // Program Counter Register (redirects on ex_redirect, holds state on stall_pc)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_pc <= 32'h0000_0000;
        end else if (ex_redirect) begin
            if_pc <= ex_redirect_target;
        end else if (!stall_pc) begin
            if_pc <= if_pc_next;
        end
    end

    // Instruction Memory Instance
    instruction_memory #(
        .WORDS(256)
    ) imem (
        .addr(if_pc),
        .instr(if_instr)
    );

    // -------------------------------------------------------------------------
    // IF/ID Pipeline Register (holds state on stall_if_id, flushes on flush_if_id)
    // -------------------------------------------------------------------------
    logic [31:0] id_pc;
    logic [31:0] id_pc_plus_4;
    logic [31:0] id_instr;

    pipe_reg_if_id pipe_if_id (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall_if_id),
        .flush(flush_if_id),
        .if_pc(if_pc),
        .if_pc_plus_4(if_pc_plus_4),
        .if_instr(if_instr),
        .id_pc(id_pc),
        .id_pc_plus_4(id_pc_plus_4),
        .id_instr(id_instr)
    );

    // =========================================================================
    // STAGE 2: INSTRUCTION DECODE (ID)
    // =========================================================================
    logic [6:0] id_opcode;
    logic [4:0] id_rd;
    logic [2:0] id_funct3;
    logic [4:0] id_rs1;
    logic [4:0] id_rs2;
    logic       id_funct7_5;

    assign id_opcode   = id_instr[6:0];
    assign id_rd       = id_instr[11:7];
    assign id_funct3   = id_instr[14:12];
    assign id_rs1      = id_instr[19:15];
    assign id_rs2      = id_instr[24:20];
    assign id_funct7_5 = id_instr[30];

    // Instruction Class Decodes
    logic id_is_lui;
    logic id_is_auipc;
    logic id_is_jal;
    logic id_is_jalr;

    assign id_is_lui   = (id_opcode == 7'b0110111);
    assign id_is_auipc = (id_opcode == 7'b0010111);
    assign id_is_jal   = (id_opcode == 7'b1101111);
    assign id_is_jalr  = (id_opcode == 7'b1100111);

    // Control Unit Instance
    logic       id_reg_write;
    logic       id_mem_read;
    logic       id_mem_write;
    logic       id_mem_to_reg;
    logic       id_alu_src;
    logic       id_branch;
    logic       id_jump;
    logic [2:0] id_imm_src;
    logic [1:0] id_alu_op;

    control_unit ctrl_unit (
        .opcode(id_opcode),
        .reg_write(id_reg_write),
        .mem_read(id_mem_read),
        .mem_write(id_mem_write),
        .mem_to_reg(id_mem_to_reg),
        .alu_src(id_alu_src),
        .branch(id_branch),
        .jump(id_jump),
        .imm_src(id_imm_src),
        .alu_op(id_alu_op)
    );

    // Immediate Generator Instance
    logic [31:0] id_imm;

    imm_gen imm_generator (
        .instr(id_instr),
        .imm_src(id_imm_src),
        .imm(id_imm)
    );

    // Register File Instance
    logic [31:0] id_rs1_data_raw;
    logic [31:0] id_rs2_data_raw;
    logic [31:0] id_rs1_data;
    logic [31:0] id_rs2_data;

    // Forward declarations of WB signals for writeback port
    logic        wb_reg_write;
    logic [4:0]  wb_rd;
    logic [31:0] wb_writeback_data;

    register_file reg_file (
        .clk(clk),
        .we(wb_reg_write),
        .raddr1(id_rs1),
        .raddr2(id_rs2),
        .waddr(wb_rd),
        .wdata(wb_writeback_data),
        .rdata1(id_rs1_data_raw),
        .rdata2(id_rs2_data_raw)
    );

    // Register File Internal Write-Through Bypass (WB -> ID):
    // Eliminates write-after-read hazards when WB writes the same register ID reads.
    assign id_rs1_data = (wb_reg_write && (wb_rd != 5'd0) && (wb_rd == id_rs1)) ?
                         wb_writeback_data : id_rs1_data_raw;
    assign id_rs2_data = (wb_reg_write && (wb_rd != 5'd0) && (wb_rd == id_rs2)) ?
                         wb_writeback_data : id_rs2_data_raw;

    // -------------------------------------------------------------------------
    // ID/EX Pipeline Register
    // -------------------------------------------------------------------------
    logic        ex_reg_write;
    logic        ex_mem_to_reg;
    logic        ex_jump;
    logic        ex_is_lui;
    logic        ex_mem_read;
    logic        ex_mem_write;
    logic [1:0]  ex_alu_op;
    logic        ex_alu_src;
    logic        ex_is_auipc;
    logic        ex_branch;
    logic        ex_is_jal;
    logic        ex_is_jalr;
    logic [31:0] ex_pc;
    logic [31:0] ex_pc_plus_4;
    logic [31:0] ex_rs1_data;
    logic [31:0] ex_rs2_data;
    logic [31:0] ex_imm;
    logic [2:0]  ex_funct3;
    logic        ex_funct7_5;
    logic [4:0]  ex_rs1;
    logic [4:0]  ex_rs2;
    logic [4:0]  ex_rd;
    logic [31:0] ex_instr;

    // -------------------------------------------------------------------------
    // Hazard Detection Unit (Stage 10D / 10E)
    // -------------------------------------------------------------------------
    hazard_unit haz_unit (
        .id_instr(id_instr),
        .id_rs1(id_rs1),
        .id_rs2(id_rs2),
        .ex_mem_read(ex_mem_read),
        .ex_rd(ex_rd),
        .ex_redirect(ex_redirect),
        .stall_pc(stall_pc),
        .stall_if_id(stall_if_id),
        .flush_id_ex(flush_id_ex),
        .flush_if_id(flush_if_id),
        .load_use_hazard(load_use_hazard)
    );

    pipe_reg_id_ex pipe_id_ex (
        .clk(clk),
        .rst_n(rst_n),
        .stall(1'b0),
        .flush(flush_id_ex),
        .id_reg_write(id_reg_write),
        .id_mem_to_reg(id_mem_to_reg),
        .id_jump(id_jump),
        .id_is_lui(id_is_lui),
        .id_mem_read(id_mem_read),
        .id_mem_write(id_mem_write),
        .id_alu_op(id_alu_op),
        .id_alu_src(id_alu_src),
        .id_is_auipc(id_is_auipc),
        .id_branch(id_branch),
        .id_is_jal(id_is_jal),
        .id_is_jalr(id_is_jalr),
        .id_pc(id_pc),
        .id_pc_plus_4(id_pc_plus_4),
        .id_rs1_data(id_rs1_data),
        .id_rs2_data(id_rs2_data),
        .id_imm(id_imm),
        .id_funct3(id_funct3),
        .id_funct7_5(id_funct7_5),
        .id_rs1(id_rs1),
        .id_rs2(id_rs2),
        .id_rd(id_rd),
        .id_instr(id_instr),
        .ex_reg_write(ex_reg_write),
        .ex_mem_to_reg(ex_mem_to_reg),
        .ex_jump(ex_jump),
        .ex_is_lui(ex_is_lui),
        .ex_mem_read(ex_mem_read),
        .ex_mem_write(ex_mem_write),
        .ex_alu_op(ex_alu_op),
        .ex_alu_src(ex_alu_src),
        .ex_is_auipc(ex_is_auipc),
        .ex_branch(ex_branch),
        .ex_is_jal(ex_is_jal),
        .ex_is_jalr(ex_is_jalr),
        .ex_pc(ex_pc),
        .ex_pc_plus_4(ex_pc_plus_4),
        .ex_rs1_data(ex_rs1_data),
        .ex_rs2_data(ex_rs2_data),
        .ex_imm(ex_imm),
        .ex_funct3(ex_funct3),
        .ex_funct7_5(ex_funct7_5),
        .ex_rs1(ex_rs1),
        .ex_rs2(ex_rs2),
        .ex_rd(ex_rd),
        .ex_instr(ex_instr)
    );

    // =========================================================================
    // STAGE 3: EXECUTE (EX)
    // =========================================================================
    logic [3:0]  ex_alu_control;
    logic [31:0] ex_alu_operand_a;
    logic [31:0] ex_alu_operand_b;
    logic [31:0] ex_alu_result;
    logic        ex_alu_zero;

    // Forward declarations of EX/MEM signals for forwarding unit
    logic        mem_reg_write;
    logic        mem_mem_to_reg;
    logic        mem_jump;
    logic        mem_is_lui;
    logic        mem_mem_read;
    logic        mem_mem_write;
    logic [31:0] mem_alu_result;
    logic [31:0] mem_rs2_data;
    logic [31:0] mem_imm;
    logic [31:0] mem_pc_plus_4;
    logic [4:0]  mem_rd;
    logic [31:0] mem_pc;
    logic [31:0] mem_instr;

    // Forwarding Unit Controls and Multiplexed Operands
    logic [1:0]  forward_a;
    logic [1:0]  forward_b;
    logic [31:0] forwarded_rs1_data;
    logic [31:0] forwarded_rs2_data;
    logic [31:0] ex_mem_forward_data;

    // Instantiate Forwarding Unit
    forwarding_unit fwd_unit (
        .ex_rs1(ex_rs1),
        .ex_rs2(ex_rs2),
        .mem_reg_write(mem_reg_write),
        .mem_mem_to_reg(mem_mem_to_reg),
        .mem_rd(mem_rd),
        .wb_reg_write(wb_reg_write),
        .wb_rd(wb_rd),
        .forward_a(forward_a),
        .forward_b(forward_b)
    );

    // Assemble forwarding data from EX/MEM stage
    // Note: If instruction is a Load (mem_mem_to_reg==1), data is not ready,
    // and forwarding_unit suppresses 2'b10 forwarding.
    always_comb begin
        if (mem_jump) begin
            ex_mem_forward_data = mem_pc_plus_4;
        end else if (mem_is_lui) begin
            ex_mem_forward_data = mem_imm;
        end else begin
            ex_mem_forward_data = mem_alu_result;
        end
    end

    // Forwarding Mux for Operand A (rs1)
    always_comb begin
        case (forward_a)
            2'b10:   forwarded_rs1_data = ex_mem_forward_data;
            2'b01:   forwarded_rs1_data = wb_writeback_data;
            default: forwarded_rs1_data = ex_rs1_data;
        endcase
    end

    // Forwarding Mux for Operand B (rs2) & Store Data
    always_comb begin
        case (forward_b)
            2'b10:   forwarded_rs2_data = ex_mem_forward_data;
            2'b01:   forwarded_rs2_data = wb_writeback_data;
            default: forwarded_rs2_data = ex_rs2_data;
        endcase
    end

    alu_decoder alu_dec (
        .alu_op(ex_alu_op),
        .funct3(ex_funct3),
        .funct7_5(ex_funct7_5),
        .alu_control(ex_alu_control)
    );

    // Operand A: PC for AUIPC, otherwise forwarded_rs1_data
    assign ex_alu_operand_a = (ex_is_auipc) ? ex_pc : forwarded_rs1_data;

    // Operand B: Immediate if alu_src asserted, otherwise forwarded_rs2_data
    assign ex_alu_operand_b = (ex_alu_src) ? ex_imm : forwarded_rs2_data;

    alu core_alu (
        .a(ex_alu_operand_a),
        .b(ex_alu_operand_b),
        .alu_op(ex_alu_control),
        .alu_result(ex_alu_result),
        .zero(ex_alu_zero)
    );

    // -------------------------------------------------------------------------
    // Branch Decision Logic (Stage 10E)
    // Resolves conditional branches in EX stage using forwarded operand values.
    // -------------------------------------------------------------------------
    logic branch_taken;

    always_comb begin
        if (ex_branch) begin
            case (ex_funct3)
                3'b000:  branch_taken = (forwarded_rs1_data == forwarded_rs2_data);                          // BEQ
                3'b001:  branch_taken = (forwarded_rs1_data != forwarded_rs2_data);                          // BNE
                3'b100:  branch_taken = ($signed(forwarded_rs1_data) < $signed(forwarded_rs2_data));         // BLT (signed)
                3'b101:  branch_taken = ($signed(forwarded_rs1_data) >= $signed(forwarded_rs2_data));        // BGE (signed)
                3'b110:  branch_taken = (forwarded_rs1_data < forwarded_rs2_data);                          // BLTU (unsigned)
                3'b111:  branch_taken = (forwarded_rs1_data >= forwarded_rs2_data);                         // BGEU (unsigned)
                default: branch_taken = 1'b0;
            endcase
        end else begin
            branch_taken = 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Branch & Jump Target Generation and Redirection (Stage 10E)
    // -------------------------------------------------------------------------
    always_comb begin
        if (ex_branch && branch_taken) begin
            ex_redirect        = 1'b1;
            ex_redirect_target = ex_pc + ex_imm;
        end else if (ex_is_jal) begin
            ex_redirect        = 1'b1;
            ex_redirect_target = ex_pc + ex_imm;
        end else if (ex_is_jalr) begin
            ex_redirect        = 1'b1;
            ex_redirect_target = (forwarded_rs1_data + ex_imm) & ~32'd1;
        end else begin
            ex_redirect        = 1'b0;
            ex_redirect_target = 32'h0000_0000;
        end
    end

    // -------------------------------------------------------------------------
    // EX/MEM Pipeline Register
    // -------------------------------------------------------------------------

    pipe_reg_ex_mem pipe_ex_mem (
        .clk(clk),
        .rst_n(rst_n),
        .stall(1'b0),
        .flush(1'b0),
        .ex_reg_write(ex_reg_write),
        .ex_mem_to_reg(ex_mem_to_reg),
        .ex_jump(ex_jump),
        .ex_is_lui(ex_is_lui),
        .ex_mem_read(ex_mem_read),
        .ex_mem_write(ex_mem_write),
        .ex_alu_result(ex_alu_result),
        .ex_rs2_data(forwarded_rs2_data),
        .ex_imm(ex_imm),
        .ex_pc_plus_4(ex_pc_plus_4),
        .ex_rd(ex_rd),
        .ex_pc(ex_pc),
        .ex_instr(ex_instr),
        .mem_reg_write(mem_reg_write),
        .mem_mem_to_reg(mem_mem_to_reg),
        .mem_jump(mem_jump),
        .mem_is_lui(mem_is_lui),
        .mem_mem_read(mem_mem_read),
        .mem_mem_write(mem_mem_write),
        .mem_alu_result(mem_alu_result),
        .mem_rs2_data(mem_rs2_data),
        .mem_imm(mem_imm),
        .mem_pc_plus_4(mem_pc_plus_4),
        .mem_rd(mem_rd),
        .mem_pc(mem_pc),
        .mem_instr(mem_instr)
    );

    // =========================================================================
    // STAGE 4: MEMORY ACCESS (MEM)
    // =========================================================================
    logic [31:0] mem_read_data;

    data_memory #(
        .WORDS(256)
    ) dmem (
        .clk(clk),
        .mem_read(mem_mem_read),
        .mem_write(mem_mem_write),
        .addr(mem_alu_result),
        .write_data(mem_rs2_data),
        .read_data(mem_read_data)
    );

    // -------------------------------------------------------------------------
    // MEM/WB Pipeline Register
    // -------------------------------------------------------------------------
    logic        wb_mem_to_reg;
    logic        wb_jump;
    logic        wb_is_lui;
    logic [31:0] wb_mem_read_data;
    logic [31:0] wb_alu_result;
    logic [31:0] wb_imm;
    logic [31:0] wb_pc_plus_4;
    logic [31:0] wb_pc;
    logic [31:0] wb_instr;

    pipe_reg_mem_wb pipe_mem_wb (
        .clk(clk),
        .rst_n(rst_n),
        .stall(1'b0),
        .flush(1'b0),
        .mem_reg_write(mem_reg_write),
        .mem_mem_to_reg(mem_mem_to_reg),
        .mem_jump(mem_jump),
        .mem_is_lui(mem_is_lui),
        .mem_read_data(mem_read_data),
        .mem_alu_result(mem_alu_result),
        .mem_imm(mem_imm),
        .mem_pc_plus_4(mem_pc_plus_4),
        .mem_rd(mem_rd),
        .mem_pc(mem_pc),
        .mem_instr(mem_instr),
        .wb_reg_write(wb_reg_write),
        .wb_mem_to_reg(wb_mem_to_reg),
        .wb_jump(wb_jump),
        .wb_is_lui(wb_is_lui),
        .wb_mem_read_data(wb_mem_read_data),
        .wb_alu_result(wb_alu_result),
        .wb_imm(wb_imm),
        .wb_pc_plus_4(wb_pc_plus_4),
        .wb_rd(wb_rd),
        .wb_pc(wb_pc),
        .wb_instr(wb_instr)
    );

    // =========================================================================
    // STAGE 5: WRITEBACK (WB)
    // =========================================================================
    always_comb begin
        if (wb_mem_to_reg) begin
            wb_writeback_data = wb_mem_read_data;
        end else if (wb_jump) begin
            wb_writeback_data = wb_pc_plus_4;
        end else if (wb_is_lui) begin
            wb_writeback_data = wb_imm;
        end else begin
            wb_writeback_data = wb_alu_result;
        end
    end

endmodule
