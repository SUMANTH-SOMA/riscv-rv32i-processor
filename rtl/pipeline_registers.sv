`timescale 1ns / 1ps

// =============================================================================
// Module: pipeline_registers
// Project: RV32I RISC-V Processor (Stage 10B)
// Description:
//   Synchronous pipeline register stages for 5-stage RV32I processor:
//     1. pipe_reg_if_id  : IF -> ID register
//     2. pipe_reg_id_ex  : ID -> EX register
//     3. pipe_reg_ex_mem : EX -> MEM register
//     4. pipe_reg_mem_wb : MEM -> WB register
//
// Key Architectural Features:
//   - Synchronous positive-edge clocking (posedge clk).
//   - Active-low asynchronous reset (negedge rst_n).
//   - Synchronous stall (enable) control: holds register state.
//   - Synchronous flush (bubble insertion) control: injects NOP (32'h00000013)
//     and zeros all control signals.
//   - Preserves load metadata (mem_to_reg, mem_read) across stages to support
//     future load-use detection and forwarding differentiation.
//   - Propagates PC and instruction words across all stages for pipeline
//     observability and debug tracking.
// =============================================================================

// -----------------------------------------------------------------------------
// 1. IF/ID Pipeline Register
// -----------------------------------------------------------------------------
module pipe_reg_if_id (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        stall,          // Hold current state
    input  logic        flush,          // Clear to NOP bubble
    input  logic [31:0] if_pc,
    input  logic [31:0] if_pc_plus_4,
    input  logic [31:0] if_instr,
    output logic [31:0] id_pc,
    output logic [31:0] id_pc_plus_4,
    output logic [31:0] id_instr
);

    localparam logic [31:0] NOP_INSTR = 32'h0000_0013; // addi x0, x0, 0

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_pc        <= 32'h0000_0000;
            id_pc_plus_4 <= 32'h0000_0004;
            id_instr     <= NOP_INSTR;
        end else if (flush) begin
            id_pc        <= 32'h0000_0000;
            id_pc_plus_4 <= 32'h0000_0004;
            id_instr     <= NOP_INSTR;
        end else if (!stall) begin
            id_pc        <= if_pc;
            id_pc_plus_4 <= if_pc_plus_4;
            id_instr     <= if_instr;
        end
    end

endmodule


// -----------------------------------------------------------------------------
// 2. ID/EX Pipeline Register
// -----------------------------------------------------------------------------
module pipe_reg_id_ex (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        stall,          // Hold current state
    input  logic        flush,          // Clear to bubble (zero controls)

    // WB Stage Control Signals
    input  logic        id_reg_write,
    input  logic        id_mem_to_reg,
    input  logic        id_jump,
    input  logic        id_is_lui,

    // MEM Stage Control Signals
    input  logic        id_mem_read,
    input  logic        id_mem_write,

    // EX Stage Control Signals
    input  logic [1:0]  id_alu_op,
    input  logic        id_alu_src,
    input  logic        id_is_auipc,
    input  logic        id_branch,
    input  logic        id_is_jal,
    input  logic        id_is_jalr,

    // Datapath Signals
    input  logic [31:0] id_pc,
    input  logic [31:0] id_pc_plus_4,
    input  logic [31:0] id_rs1_data,
    input  logic [31:0] id_rs2_data,
    input  logic [31:0] id_imm,
    input  logic [2:0]  id_funct3,
    input  logic        id_funct7_5,
    input  logic [4:0]  id_rs1,
    input  logic [4:0]  id_rs2,
    input  logic [4:0]  id_rd,
    input  logic [31:0] id_instr,

    // Outputs to EX Stage
    output logic        ex_reg_write,
    output logic        ex_mem_to_reg,
    output logic        ex_jump,
    output logic        ex_is_lui,
    output logic        ex_mem_read,
    output logic        ex_mem_write,
    output logic [1:0]  ex_alu_op,
    output logic        ex_alu_src,
    output logic        ex_is_auipc,
    output logic        ex_branch,
    output logic        ex_is_jal,
    output logic        ex_is_jalr,
    output logic [31:0] ex_pc,
    output logic [31:0] ex_pc_plus_4,
    output logic [31:0] ex_rs1_data,
    output logic [31:0] ex_rs2_data,
    output logic [31:0] ex_imm,
    output logic [2:0]  ex_funct3,
    output logic        ex_funct7_5,
    output logic [4:0]  ex_rs1,
    output logic [4:0]  ex_rs2,
    output logic [4:0]  ex_rd,
    output logic [31:0] ex_instr
);

    localparam logic [31:0] NOP_INSTR = 32'h0000_0013;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            ex_reg_write  <= 1'b0;
            ex_mem_to_reg <= 1'b0;
            ex_jump       <= 1'b0;
            ex_is_lui     <= 1'b0;
            ex_mem_read   <= 1'b0;
            ex_mem_write  <= 1'b0;
            ex_alu_op     <= 2'b00;
            ex_alu_src    <= 1'b0;
            ex_is_auipc   <= 1'b0;
            ex_branch     <= 1'b0;
            ex_is_jal     <= 1'b0;
            ex_is_jalr    <= 1'b0;
            ex_pc         <= 32'h0000_0000;
            ex_pc_plus_4  <= 32'h0000_0004;
            ex_rs1_data   <= 32'h0000_0000;
            ex_rs2_data   <= 32'h0000_0000;
            ex_imm        <= 32'h0000_0000;
            ex_funct3     <= 3'b000;
            ex_funct7_5   <= 1'b0;
            ex_rs1        <= 5'd0;
            ex_rs2        <= 5'd0;
            ex_rd         <= 5'd0;
            ex_instr      <= NOP_INSTR;
        end else if (!stall) begin
            ex_reg_write  <= id_reg_write;
            ex_mem_to_reg <= id_mem_to_reg;
            ex_jump       <= id_jump;
            ex_is_lui     <= id_is_lui;
            ex_mem_read   <= id_mem_read;
            ex_mem_write  <= id_mem_write;
            ex_alu_op     <= id_alu_op;
            ex_alu_src    <= id_alu_src;
            ex_is_auipc   <= id_is_auipc;
            ex_branch     <= id_branch;
            ex_is_jal     <= id_is_jal;
            ex_is_jalr    <= id_is_jalr;
            ex_pc         <= id_pc;
            ex_pc_plus_4  <= id_pc_plus_4;
            ex_rs1_data   <= id_rs1_data;
            ex_rs2_data   <= id_rs2_data;
            ex_imm        <= id_imm;
            ex_funct3     <= id_funct3;
            ex_funct7_5   <= id_funct7_5;
            ex_rs1        <= id_rs1;
            ex_rs2        <= id_rs2;
            ex_rd         <= id_rd;
            ex_instr      <= id_instr;
        end
    end

endmodule


// -----------------------------------------------------------------------------
// 3. EX/MEM Pipeline Register
// -----------------------------------------------------------------------------
module pipe_reg_ex_mem (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        stall,          // Hold current state
    input  logic        flush,          // Clear to bubble

    // WB Stage Control Signals
    input  logic        ex_reg_write,
    input  logic        ex_mem_to_reg,
    input  logic        ex_jump,
    input  logic        ex_is_lui,

    // MEM Stage Control Signals (preserved metadata for load distinction)
    input  logic        ex_mem_read,
    input  logic        ex_mem_write,

    // Datapath Signals
    input  logic [31:0] ex_alu_result,
    input  logic [31:0] ex_rs2_data,
    input  logic [31:0] ex_imm,
    input  logic [31:0] ex_pc_plus_4,
    input  logic [4:0]  ex_rd,
    input  logic [31:0] ex_pc,
    input  logic [31:0] ex_instr,

    // Outputs to MEM Stage
    output logic        mem_reg_write,
    output logic        mem_mem_to_reg,
    output logic        mem_jump,
    output logic        mem_is_lui,
    output logic        mem_mem_read,
    output logic        mem_mem_write,
    output logic [31:0] mem_alu_result,
    output logic [31:0] mem_rs2_data,
    output logic [31:0] mem_imm,
    output logic [31:0] mem_pc_plus_4,
    output logic [4:0]  mem_rd,
    output logic [31:0] mem_pc,
    output logic [31:0] mem_instr
);

    localparam logic [31:0] NOP_INSTR = 32'h0000_0013;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            mem_reg_write  <= 1'b0;
            mem_mem_to_reg <= 1'b0;
            mem_jump       <= 1'b0;
            mem_is_lui     <= 1'b0;
            mem_mem_read   <= 1'b0;
            mem_mem_write  <= 1'b0;
            mem_alu_result <= 32'h0000_0000;
            mem_rs2_data   <= 32'h0000_0000;
            mem_imm        <= 32'h0000_0000;
            mem_pc_plus_4  <= 32'h0000_0004;
            mem_rd         <= 5'd0;
            mem_pc         <= 32'h0000_0000;
            mem_instr      <= NOP_INSTR;
        end else if (!stall) begin
            mem_reg_write  <= ex_reg_write;
            mem_mem_to_reg <= ex_mem_to_reg;
            mem_jump       <= ex_jump;
            mem_is_lui     <= ex_is_lui;
            mem_mem_read   <= ex_mem_read;
            mem_mem_write  <= ex_mem_write;
            mem_alu_result <= ex_alu_result;
            mem_rs2_data   <= ex_rs2_data;
            mem_imm        <= ex_imm;
            mem_pc_plus_4  <= ex_pc_plus_4;
            mem_rd         <= ex_rd;
            mem_pc         <= ex_pc;
            mem_instr      <= ex_instr;
        end
    end

endmodule


// -----------------------------------------------------------------------------
// 4. MEM/WB Pipeline Register
// -----------------------------------------------------------------------------
module pipe_reg_mem_wb (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        stall,          // Hold current state
    input  logic        flush,          // Clear to bubble

    // WB Stage Control Signals
    input  logic        mem_reg_write,
    input  logic        mem_mem_to_reg,
    input  logic        mem_jump,
    input  logic        mem_is_lui,

    // Datapath Signals
    input  logic [31:0] mem_read_data,
    input  logic [31:0] mem_alu_result,
    input  logic [31:0] mem_imm,
    input  logic [31:0] mem_pc_plus_4,
    input  logic [4:0]  mem_rd,
    input  logic [31:0] mem_pc,
    input  logic [31:0] mem_instr,

    // Outputs to WB Stage
    output logic        wb_reg_write,
    output logic        wb_mem_to_reg,
    output logic        wb_jump,
    output logic        wb_is_lui,
    output logic [31:0] wb_mem_read_data,
    output logic [31:0] wb_alu_result,
    output logic [31:0] wb_imm,
    output logic [31:0] wb_pc_plus_4,
    output logic [4:0]  wb_rd,
    output logic [31:0] wb_pc,
    output logic [31:0] wb_instr
);

    localparam logic [31:0] NOP_INSTR = 32'h0000_0013;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            wb_reg_write     <= 1'b0;
            wb_mem_to_reg    <= 1'b0;
            wb_jump          <= 1'b0;
            wb_is_lui        <= 1'b0;
            wb_mem_read_data <= 32'h0000_0000;
            wb_alu_result    <= 32'h0000_0000;
            wb_imm           <= 32'h0000_0000;
            wb_pc_plus_4     <= 32'h0000_0004;
            wb_rd            <= 5'd0;
            wb_pc            <= 32'h0000_0000;
            wb_instr         <= NOP_INSTR;
        end else if (!stall) begin
            wb_reg_write     <= mem_reg_write;
            wb_mem_to_reg    <= mem_mem_to_reg;
            wb_jump          <= mem_jump;
            wb_is_lui        <= mem_is_lui;
            wb_mem_read_data <= mem_read_data;
            wb_alu_result    <= mem_alu_result;
            wb_imm           <= mem_imm;
            wb_pc_plus_4     <= mem_pc_plus_4;
            wb_rd            <= mem_rd;
            wb_pc            <= mem_pc;
            wb_instr         <= mem_instr;
        end
    end

endmodule
