`timescale 1ns / 1ps

// =============================================================================
// Module: tb_benchmark
// Project: RV32I RISC-V Processor (Stage 10F Performance Benchmarking)
// Description:
//   Self-checking comparative performance benchmark testbench evaluating
//   the Single-Cycle RV32I CPU against the Five-Stage Pipelined RV32I CPU.
//
// Workload Suite:
//   1. BENCH_ALU       : Intensive arithmetic & RAW forwarding stress test
//   2. BENCH_MEM       : Memory load/store & load-use stall penalty benchmark
//   3. BENCH_BRANCH    : Control-flow loop & branch resolution benchmark
//   4. BENCH_COMPOSITE : Realistic array accumulation & maximum value search
//
// Metrics Collected:
//   - Dynamic retired instructions (I)
//   - Elapsed clock cycles (C_single, C_pipe)
//   - Cycles Per Instruction (CPI_single, CPI_pipe)
//   - Cycle-count speedup (S_cycle = C_single / C_pipe)
//   - Pipeline pipeline-fill, stall, and flush overhead breakdown
//   - 100% Architectural state equivalence verification
// =============================================================================

module tb_benchmark;

    // Simulation Clocks and Resets
    logic clk;
    logic rst_n_single;
    logic rst_n_pipe;

    // CPU Top Probes
    logic [31:0] pc_out_single;
    logic [31:0] instr_out_single;
    logic [31:0] pc_out_pipe;
    logic [31:0] instr_out_pipe;

    // Instantiate Single-Cycle Reference CPU
    cpu u_single_cpu (
        .clk(clk),
        .rst_n(rst_n_single),
        .pc_out(pc_out_single),
        .instr_out(instr_out_single)
    );

    // Instantiate Five-Stage Pipelined CPU
    cpu_pipeline u_pipe_cpu (
        .clk(clk),
        .rst_n(rst_n_pipe),
        .pc_out(pc_out_pipe),
        .instr_out(instr_out_pipe)
    );

    // 100 MHz System Clock (10ns period: 5ns high, 5ns low)
    initial clk = 1'b0;
    always #5 clk = ~clk;

    localparam logic [31:0] NOP_INSTR = 32'h0000_0013;

    // Benchmark Result Arrays (Icarus Verilog compatible)
    string bench_name[0:3];
    int    inst_count[0:3];
    int    cycles_single[0:3];
    int    cycles_pipe[0:3];
    real   cpi_single[0:3];
    real   cpi_pipe[0:3];
    real   speedup_cycle[0:3];
    int    fill_cycles[0:3];
    int    stall_cycles[0:3];
    int    flush_cycles[0:3];
    int    fwd_ex_mem_count[0:3];
    int    fwd_mem_wb_count[0:3];
    bit    state_match[0:3];

    int total_benchmarks_passed = 0;

    // Task: Clear memory and register state for both CPUs
    task clear_all_state();
        begin
            for (int i = 0; i < 32; i++) begin
                u_single_cpu.reg_file.regs[i] = 32'd0;
                u_pipe_cpu.reg_file.regs[i]   = 32'd0;
            end
            for (int i = 0; i < 64; i++) begin
                u_single_cpu.dmem.mem[i] = 32'd0;
                u_pipe_cpu.dmem.mem[i]   = 32'd0;
            end
            for (int i = 0; i < 128; i++) begin
                u_single_cpu.imem.mem[i] = NOP_INSTR;
                u_pipe_cpu.imem.mem[i]   = NOP_INSTR;
            end
        end
    endtask

    // Task: Verify architectural register and memory equivalence
    task verify_equivalence(
        input  string test_name,
        output bit    is_match
    );
        int reg_mismatches;
        int dmem_mismatches;
        begin
            reg_mismatches  = 0;
            dmem_mismatches = 0;

            for (int i = 0; i < 32; i++) begin
                if (u_single_cpu.reg_file.regs[i] !== u_pipe_cpu.reg_file.regs[i]) begin
                    reg_mismatches++;
                    $display("  [MISMATCH] Register x%0d: Single=0x%08h, Pipe=0x%08h",
                             i, u_single_cpu.reg_file.regs[i], u_pipe_cpu.reg_file.regs[i]);
                end
            end

            for (int i = 0; i < 64; i++) begin
                if (u_single_cpu.dmem.mem[i] !== u_pipe_cpu.dmem.mem[i]) begin
                    dmem_mismatches++;
                    $display("  [MISMATCH] DataMem[%0d]: Single=0x%08h, Pipe=0x%08h",
                             i, u_single_cpu.dmem.mem[i], u_pipe_cpu.dmem.mem[i]);
                end
            end

            if (reg_mismatches == 0 && dmem_mismatches == 0) begin
                is_match = 1'b1;
                $display("  [EQUIVALENCE CHECK PASSED] %s: Architectural state identical across all registers & data memory.", test_name);
            end else begin
                is_match = 1'b0;
                $display("  [EQUIVALENCE CHECK FAILED] %s: %0d register and %0d memory mismatches detected!",
                         test_name, reg_mismatches, dmem_mismatches);
            end
        end
    endtask

    // =========================================================================
    // Benchmark 1: Arithmetic & RAW Forwarding Stress (BENCH_ALU)
    // =========================================================================
    task run_benchmark_alu(input int idx);
        int single_cycles;
        int pipe_cycles;
        int stall_cnt;
        int flush_cnt;
        int fwd_ex_mem_cnt;
        int fwd_mem_wb_cnt;
        bit match;
        logic [31:0] halt_pc;
        begin
            bench_name[idx] = "BENCH_ALU (Arithmetic & Forwarding)";
            halt_pc  = 32'h0000_0050; // Word 20 = 0x50

            clear_all_state();

            // Word 0 (0x00): addi x1, x0, 10
            u_single_cpu.imem.mem[0] = 32'h00A0_0093; u_pipe_cpu.imem.mem[0] = 32'h00A0_0093;
            // Word 1 (0x04): addi x2, x0, 20
            u_single_cpu.imem.mem[1] = 32'h0140_0113; u_pipe_cpu.imem.mem[1] = 32'h0140_0113;
            // Word 2 (0x08): add  x3, x1, x2 (EX/MEM forward x2, MEM/WB forward x1)
            u_single_cpu.imem.mem[2] = 32'h0020_81B3; u_pipe_cpu.imem.mem[2] = 32'h0020_81B3;
            // Word 3 (0x0C): sub  x4, x3, x1 (EX/MEM forward x3)
            u_single_cpu.imem.mem[3] = 32'h4011_8233; u_pipe_cpu.imem.mem[3] = 32'h4011_8233;
            // Word 4 (0x10): sll  x5, x1, x3 (MEM/WB forward x3)
            u_single_cpu.imem.mem[4] = 32'h0030_92B3; u_pipe_cpu.imem.mem[4] = 32'h0030_92B3;
            // Word 5 (0x14): slt  x6, x4, x3 (EX/MEM forward x4)
            u_single_cpu.imem.mem[5] = 32'h0032_2333; u_pipe_cpu.imem.mem[5] = 32'h0032_2333;
            // Word 6 (0x18): sltu x7, x5, x4 (EX/MEM forward x5, MEM/WB forward x4)
            u_single_cpu.imem.mem[6] = 32'h0042_B3B3; u_pipe_cpu.imem.mem[6] = 32'h0042_B3B3;
            // Word 7 (0x1C): xor  x8, x4, x2
            u_single_cpu.imem.mem[7] = 32'h0022_4433; u_pipe_cpu.imem.mem[7] = 32'h0022_4433;
            // Word 8 (0x20): srl  x9, x5, x1
            u_single_cpu.imem.mem[8] = 32'h0012_D4B3; u_pipe_cpu.imem.mem[8] = 32'h0012_D4B3;
            // Word 9 (0x24): sra  x10, x5, x1
            u_single_cpu.imem.mem[9] = 32'h4012_D533; u_pipe_cpu.imem.mem[9] = 32'h4012_D533;
            // Word 10(0x28): or   x11, x8, x6
            u_single_cpu.imem.mem[10] = 32'h0064_65B3; u_pipe_cpu.imem.mem[10] = 32'h0064_65B3;
            // Word 11(0x2C): and  x12, x10, x9 (EX/MEM forward x10, MEM/WB forward x9)
            u_single_cpu.imem.mem[11] = 32'h0095_7633; u_pipe_cpu.imem.mem[11] = 32'h0095_7633;
            // Word 12(0x30): addi x13, x12, 1 (EX/MEM forward x12)
            u_single_cpu.imem.mem[12] = 32'h0016_06B3; u_pipe_cpu.imem.mem[12] = 32'h0016_06B3;
            // Word 13(0x34): add  x14, x13, x11 (EX/MEM forward x13)
            u_single_cpu.imem.mem[13] = 32'h00B6_8733; u_pipe_cpu.imem.mem[13] = 32'h00B6_8733;
            // Word 14(0x38): sub  x15, x14, x1 (EX/MEM forward x14)
            u_single_cpu.imem.mem[14] = 32'h4017_07B3; u_pipe_cpu.imem.mem[14] = 32'h4017_07B3;
            // Word 15(0x3C): addi x16, x15, 5 (EX/MEM forward x15)
            u_single_cpu.imem.mem[15] = 32'h0057_8833; u_pipe_cpu.imem.mem[15] = 32'h0057_8833;
            // Word 16(0x40): and  x17, x16, x2 (EX/MEM forward x16)
            u_single_cpu.imem.mem[16] = 32'h0028_78B3; u_pipe_cpu.imem.mem[16] = 32'h0028_78B3;
            // Word 17(0x44): or   x18, x17, x1 (EX/MEM forward x17)
            u_single_cpu.imem.mem[17] = 32'h0018_E933; u_pipe_cpu.imem.mem[17] = 32'h0018_E933;
            // Word 18(0x48): xor  x19, x18, x3 (EX/MEM forward x18)
            u_single_cpu.imem.mem[18] = 32'h0039_49B3; u_pipe_cpu.imem.mem[18] = 32'h0039_49B3;
            // Word 19(0x4C): addi x20, x19, 100 (EX/MEM forward x19)
            u_single_cpu.imem.mem[19] = 32'h0649_8A13; u_pipe_cpu.imem.mem[19] = 32'h0649_8A13;
            // Word 20(0x50): beq  x0, x0, 0 (Halt self-loop)
            u_single_cpu.imem.mem[20] = 32'h0000_0063; u_pipe_cpu.imem.mem[20] = 32'h0000_0063;

            // --- 1. Run Single-Cycle CPU ---
            rst_n_single = 1'b0;
            repeat (2) @(posedge clk);
            #1; rst_n_single = 1'b1;

            single_cycles = 0;
            while ((u_single_cpu.pc_out !== halt_pc) && (single_cycles < 200)) begin
                @(posedge clk);
                single_cycles++;
            end

            // --- 2. Run Pipelined CPU ---
            rst_n_pipe = 1'b0;
            repeat (2) @(posedge clk);
            #1; rst_n_pipe = 1'b1;

            pipe_cycles    = 0;
            stall_cnt      = 0;
            flush_cnt      = 0;
            fwd_ex_mem_cnt = 0;
            fwd_mem_wb_cnt = 0;

            while ((u_pipe_cpu.pipe_mem_wb.wb_pc !== halt_pc) && (pipe_cycles < 200)) begin
                @(posedge clk);
                pipe_cycles++;

                if (u_pipe_cpu.load_use_hazard)
                    stall_cnt++;
                if (u_pipe_cpu.ex_redirect && (u_pipe_cpu.ex_pc !== halt_pc))
                    flush_cnt += 2;
                if (u_pipe_cpu.forward_a == 2'b10 || u_pipe_cpu.forward_b == 2'b10)
                    fwd_ex_mem_cnt++;
                if (u_pipe_cpu.forward_a == 2'b01 || u_pipe_cpu.forward_b == 2'b01)
                    fwd_mem_wb_cnt++;
            end

            verify_equivalence(bench_name[idx], match);

            inst_count[idx]       = single_cycles; // 20 instructions
            cycles_single[idx]    = single_cycles;
            cycles_pipe[idx]      = pipe_cycles;
            cpi_single[idx]       = real'(single_cycles) / real'(single_cycles);
            cpi_pipe[idx]         = real'(pipe_cycles) / real'(single_cycles);
            speedup_cycle[idx]    = real'(single_cycles) / real'(pipe_cycles);
            fill_cycles[idx]      = 4;
            stall_cycles[idx]     = stall_cnt;
            flush_cycles[idx]     = flush_cnt;
            fwd_ex_mem_count[idx] = fwd_ex_mem_cnt;
            fwd_mem_wb_count[idx] = fwd_mem_wb_cnt;
            state_match[idx]      = match;
        end
    endtask

    // =========================================================================
    // Benchmark 2: Memory & Load-Use Stalls (BENCH_MEM)
    // =========================================================================
    task run_benchmark_mem(input int idx);
        int single_cycles;
        int pipe_cycles;
        int stall_cnt;
        int flush_cnt;
        int fwd_ex_mem_cnt;
        int fwd_mem_wb_cnt;
        bit match;
        logic [31:0] halt_pc;
        begin
            bench_name[idx] = "BENCH_MEM (Load/Store & Stalling)";
            halt_pc  = 32'h0000_0044; // Word 17 = 0x44

            clear_all_state();

            // Word 0 (0x00): addi x1, x0, 50
            u_single_cpu.imem.mem[0] = 32'h0320_0093; u_pipe_cpu.imem.mem[0] = 32'h0320_0093;
            // Word 1 (0x04): sw   x1, 16(x0) (Mem[4] <= 50)
            u_single_cpu.imem.mem[1] = 32'h0010_2823; u_pipe_cpu.imem.mem[1] = 32'h0010_2823;
            // Word 2 (0x08): addi x2, x0, 75
            u_single_cpu.imem.mem[2] = 32'h04B0_0113; u_pipe_cpu.imem.mem[2] = 32'h04B0_0113;
            // Word 3 (0x0C): sw   x2, 20(x0) (Mem[5] <= 75)
            u_single_cpu.imem.mem[3] = 32'h0020_2A23; u_pipe_cpu.imem.mem[3] = 32'h0020_2A23;
            // Word 4 (0x10): lw   x3, 16(x0) (x3 <= 50)
            u_single_cpu.imem.mem[4] = 32'h0100_2183; u_pipe_cpu.imem.mem[4] = 32'h0100_2183;
            // Word 5 (0x14): addi x4, x3, 10 (LOAD-USE STALL #1: x4 <= 60)
            u_single_cpu.imem.mem[5] = 32'h00A1_8213; u_pipe_cpu.imem.mem[5] = 32'h00A1_8213;
            // Word 6 (0x18): sw   x4, 24(x0) (Mem[6] <= 60)
            u_single_cpu.imem.mem[6] = 32'h0040_2C23; u_pipe_cpu.imem.mem[6] = 32'h0040_2C23;
            // Word 7 (0x1C): lw   x5, 20(x0) (x5 <= 75)
            u_single_cpu.imem.mem[7] = 32'h0140_2283; u_pipe_cpu.imem.mem[7] = 32'h0140_2283;
            // Word 8 (0x20): sub  x6, x5, x3 (LOAD-USE STALL #2: x6 <= 25)
            u_single_cpu.imem.mem[8] = 32'h4032_8333; u_pipe_cpu.imem.mem[8] = 32'h4032_8333;
            // Word 9 (0x24): lw   x7, 16(x0) (x7 <= 50)
            u_single_cpu.imem.mem[9] = 32'h0100_2383; u_pipe_cpu.imem.mem[9] = 32'h0100_2383;
            // Word 10(0x28): addi x8, x0, 5  (Separating instruction: x8 <= 5)
            u_single_cpu.imem.mem[10] = 32'h0050_0413; u_pipe_cpu.imem.mem[10] = 32'h0050_0413;
            // Word 11(0x2C): add  x9, x7, x8 (NO STALL: separated by 1 cycle, x9 <= 55)
            u_single_cpu.imem.mem[11] = 32'h0083_84B3; u_pipe_cpu.imem.mem[11] = 32'h0083_84B3;
            // Word 12(0x30): sw   x9, 28(x0) (Mem[7] <= 55)
            u_single_cpu.imem.mem[12] = 32'h0090_2E23; u_pipe_cpu.imem.mem[12] = 32'h0090_2E23;
            // Word 13(0x34): lw   x10, 24(x0) (x10 <= 60)
            u_single_cpu.imem.mem[13] = 32'h0180_2503; u_pipe_cpu.imem.mem[13] = 32'h0180_2503;
            // Word 14(0x38): lw   x11, 28(x0) (x11 <= 55)
            u_single_cpu.imem.mem[14] = 32'h01C0_2583; u_pipe_cpu.imem.mem[14] = 32'h01C0_2583;
            // Word 15(0x3C): add  x12, x10, x11 (LOAD-USE STALL #3 on x11: x12 <= 115)
            u_single_cpu.imem.mem[15] = 32'h00B5_0633; u_pipe_cpu.imem.mem[15] = 32'h00B5_0633;
            // Word 16(0x40): sw   x12, 32(x0) (Mem[8] <= 115)
            u_single_cpu.imem.mem[16] = 32'h00C0_2023; u_pipe_cpu.imem.mem[16] = 32'h00C0_2023;
            // Word 17(0x44): beq  x0, x0, 0 (Halt self-loop)
            u_single_cpu.imem.mem[17] = 32'h0000_0063; u_pipe_cpu.imem.mem[17] = 32'h0000_0063;

            // --- 1. Run Single-Cycle CPU ---
            rst_n_single = 1'b0;
            repeat (2) @(posedge clk);
            #1; rst_n_single = 1'b1;

            single_cycles = 0;
            while ((u_single_cpu.pc_out !== halt_pc) && (single_cycles < 200)) begin
                @(posedge clk);
                single_cycles++;
            end

            // --- 2. Run Pipelined CPU ---
            rst_n_pipe = 1'b0;
            repeat (2) @(posedge clk);
            #1; rst_n_pipe = 1'b1;

            pipe_cycles    = 0;
            stall_cnt      = 0;
            flush_cnt      = 0;
            fwd_ex_mem_cnt = 0;
            fwd_mem_wb_cnt = 0;

            while ((u_pipe_cpu.pipe_mem_wb.wb_pc !== halt_pc) && (pipe_cycles < 200)) begin
                @(posedge clk);
                pipe_cycles++;

                if (u_pipe_cpu.load_use_hazard)
                    stall_cnt++;
                if (u_pipe_cpu.ex_redirect && (u_pipe_cpu.ex_pc !== halt_pc))
                    flush_cnt += 2;
                if (u_pipe_cpu.forward_a == 2'b10 || u_pipe_cpu.forward_b == 2'b10)
                    fwd_ex_mem_cnt++;
                if (u_pipe_cpu.forward_a == 2'b01 || u_pipe_cpu.forward_b == 2'b01)
                    fwd_mem_wb_cnt++;
            end

            verify_equivalence(bench_name[idx], match);

            inst_count[idx]       = single_cycles; // 17 instructions
            cycles_single[idx]    = single_cycles;
            cycles_pipe[idx]      = pipe_cycles;
            cpi_single[idx]       = real'(single_cycles) / real'(single_cycles);
            cpi_pipe[idx]         = real'(pipe_cycles) / real'(single_cycles);
            speedup_cycle[idx]    = real'(single_cycles) / real'(pipe_cycles);
            fill_cycles[idx]      = 4;
            stall_cycles[idx]     = stall_cnt;
            flush_cycles[idx]     = flush_cnt;
            fwd_ex_mem_count[idx] = fwd_ex_mem_cnt;
            fwd_mem_wb_count[idx] = fwd_mem_wb_cnt;
            state_match[idx]      = match;
        end
    endtask

    // =========================================================================
    // Benchmark 3: Control-Flow Hazards (BENCH_BRANCH)
    // =========================================================================
    task run_benchmark_branch(input int idx);
        int single_cycles;
        int pipe_cycles;
        int stall_cnt;
        int flush_cnt;
        int fwd_ex_mem_cnt;
        int fwd_mem_wb_cnt;
        bit match;
        logic [31:0] halt_pc;
        begin
            bench_name[idx] = "BENCH_BRANCH (Control Hazards & Loops)";
            halt_pc  = 32'h0000_002C; // Word 11 = 0x2C

            clear_all_state();

            // Word 0 (0x00): addi x1, x0, 5  (limit = 5)
            u_single_cpu.imem.mem[0] = 32'h0050_0093; u_pipe_cpu.imem.mem[0] = 32'h0050_0093;
            // Word 1 (0x04): addi x2, x0, 0  (i = 0)
            u_single_cpu.imem.mem[1] = 32'h0000_0113; u_pipe_cpu.imem.mem[1] = 32'h0000_0113;
            // Word 2 (0x08): addi x3, x0, 0  (sum = 0)
            u_single_cpu.imem.mem[2] = 32'h0000_0193; u_pipe_cpu.imem.mem[2] = 32'h0000_0193;

            // Loop Body:
            // Word 3 (0x0C): addi x2, x2, 1  (i = i + 1)
            u_single_cpu.imem.mem[3] = 32'h0011_0113; u_pipe_cpu.imem.mem[3] = 32'h0011_0113;
            // Word 4 (0x10): add  x3, x3, x2 (sum = sum + i)
            u_single_cpu.imem.mem[4] = 32'h0021_81B3; u_pipe_cpu.imem.mem[4] = 32'h0021_81B3;
            // Word 5 (0x14): blt  x2, x1, -8 (if i < 5 branch back to Word 3)
            u_single_cpu.imem.mem[5] = 32'hFE11_4CE3; u_pipe_cpu.imem.mem[5] = 32'hFE11_4CE3;

            // After Loop:
            // Word 6 (0x18): addi x4, x0, 15 (x4 <= 15)
            u_single_cpu.imem.mem[6] = 32'h00F0_0213; u_pipe_cpu.imem.mem[6] = 32'h00F0_0213;
            // Word 7 (0x1C): bne  x3, x4, +12 (if sum != 15 jump to Word 10: NOT TAKEN)
            u_single_cpu.imem.mem[7] = 32'h0041_9663; u_pipe_cpu.imem.mem[7] = 32'h0041_9663;
            // Word 8 (0x20): addi x5, x0, 1  (Sequential: flag x5 <= 1)
            u_single_cpu.imem.mem[8] = 32'h0010_0293; u_pipe_cpu.imem.mem[8] = 32'h0010_0293;
            // Word 9 (0x24): jal  x0, +8     (Skip error trap to Word 11)
            u_single_cpu.imem.mem[9] = 32'h0080_006F; u_pipe_cpu.imem.mem[9] = 32'h0080_006F;
            // Word 10(0x28): addi x5, x0, 0  (Error trap)
            u_single_cpu.imem.mem[10] = 32'h0000_0293; u_pipe_cpu.imem.mem[10] = 32'h0000_0293;
            // Word 11(0x2C): beq  x0, x0, 0  (Halt self-loop)
            u_single_cpu.imem.mem[11] = 32'h0000_0063; u_pipe_cpu.imem.mem[11] = 32'h0000_0063;

            // --- 1. Run Single-Cycle CPU ---
            rst_n_single = 1'b0;
            repeat (2) @(posedge clk);
            #1; rst_n_single = 1'b1;

            single_cycles = 0;
            while ((u_single_cpu.pc_out !== halt_pc) && (single_cycles < 200)) begin
                @(posedge clk);
                single_cycles++;
            end

            // --- 2. Run Pipelined CPU ---
            rst_n_pipe = 1'b0;
            repeat (2) @(posedge clk);
            #1; rst_n_pipe = 1'b1;

            pipe_cycles    = 0;
            stall_cnt      = 0;
            flush_cnt      = 0;
            fwd_ex_mem_cnt = 0;
            fwd_mem_wb_cnt = 0;

            while ((u_pipe_cpu.pipe_mem_wb.wb_pc !== halt_pc) && (pipe_cycles < 200)) begin
                @(posedge clk);
                pipe_cycles++;

                if (u_pipe_cpu.load_use_hazard)
                    stall_cnt++;
                if (u_pipe_cpu.ex_redirect && (u_pipe_cpu.ex_pc !== halt_pc))
                    flush_cnt += 2;
                if (u_pipe_cpu.forward_a == 2'b10 || u_pipe_cpu.forward_b == 2'b10)
                    fwd_ex_mem_cnt++;
                if (u_pipe_cpu.forward_a == 2'b01 || u_pipe_cpu.forward_b == 2'b01)
                    fwd_mem_wb_cnt++;
            end

            verify_equivalence(bench_name[idx], match);

            inst_count[idx]       = single_cycles; // 22 dynamic instructions
            cycles_single[idx]    = single_cycles;
            cycles_pipe[idx]      = pipe_cycles;
            cpi_single[idx]       = real'(single_cycles) / real'(single_cycles);
            cpi_pipe[idx]         = real'(pipe_cycles) / real'(single_cycles);
            speedup_cycle[idx]    = real'(single_cycles) / real'(pipe_cycles);
            fill_cycles[idx]      = 4;
            stall_cycles[idx]     = stall_cnt;
            flush_cycles[idx]     = flush_cnt;
            fwd_ex_mem_count[idx] = fwd_ex_mem_cnt;
            fwd_mem_wb_count[idx] = fwd_mem_wb_cnt;
            state_match[idx]      = match;
        end
    endtask

    // =========================================================================
    // Benchmark 4: Realistic Algorithm — Array Accumulation & Maximum Search
    // =========================================================================
    task run_benchmark_composite(input int idx);
        int single_cycles;
        int pipe_cycles;
        int stall_cnt;
        int flush_cnt;
        int fwd_ex_mem_cnt;
        int fwd_mem_wb_cnt;
        bit match;
        logic [31:0] halt_pc;
        begin
            bench_name[idx] = "BENCH_COMPOSITE (Array Accumulate & Max Search)";
            halt_pc  = 32'h0000_0038; // Word 14 = 0x38

            clear_all_state();

            // Populate test array in Data Memory: [12, 45, 23, 38]
            u_single_cpu.dmem.mem[0] = 32'd12; u_pipe_cpu.dmem.mem[0] = 32'd12;
            u_single_cpu.dmem.mem[1] = 32'd45; u_pipe_cpu.dmem.mem[1] = 32'd45;
            u_single_cpu.dmem.mem[2] = 32'd23; u_pipe_cpu.dmem.mem[2] = 32'd23;
            u_single_cpu.dmem.mem[3] = 32'd38; u_pipe_cpu.dmem.mem[3] = 32'd38;

            // Word 0 (0x00): addi x1, x0, 4   (length = 4)
            u_single_cpu.imem.mem[0] = 32'h0040_0093; u_pipe_cpu.imem.mem[0] = 32'h0040_0093;
            // Word 1 (0x04): addi x2, x0, 0   (i = 0)
            u_single_cpu.imem.mem[1] = 32'h0000_0113; u_pipe_cpu.imem.mem[1] = 32'h0000_0113;
            // Word 2 (0x08): addi x3, x0, 0   (ptr = 0)
            u_single_cpu.imem.mem[2] = 32'h0000_0193; u_pipe_cpu.imem.mem[2] = 32'h0000_0193;
            // Word 3 (0x0C): addi x4, x0, 0   (sum = 0)
            u_single_cpu.imem.mem[3] = 32'h0000_0213; u_pipe_cpu.imem.mem[3] = 32'h0000_0213;
            // Word 4 (0x10): addi x5, x0, 0   (max = 0)
            u_single_cpu.imem.mem[4] = 32'h0000_0293; u_pipe_cpu.imem.mem[4] = 32'h0000_0293;

            // Loop Header:
            // Word 5 (0x14): lw   x6, 0(x3)   (x6 <= Mem[ptr])
            u_single_cpu.imem.mem[5] = 32'h0001_A303; u_pipe_cpu.imem.mem[5] = 32'h0001_A303;
            // Word 6 (0x18): add  x4, x4, x6  (sum = sum + x6: LOAD-USE STALL)
            u_single_cpu.imem.mem[6] = 32'h0062_0233; u_pipe_cpu.imem.mem[6] = 32'h0062_0233;
            // Word 7 (0x1C): bge  x5, x6, +8  (if max >= x6 jump to Word 9 at 0x24)
            u_single_cpu.imem.mem[7] = 32'h0062_D463; u_pipe_cpu.imem.mem[7] = 32'h0062_D463;
            // Word 8 (0x20): addi x5, x6, 0   (max = x6)
            u_single_cpu.imem.mem[8] = 32'h0003_0293; u_pipe_cpu.imem.mem[8] = 32'h0003_0293;
            // Word 9 (0x24): addi x3, x3, 4   (ptr = ptr + 4)
            u_single_cpu.imem.mem[9] = 32'h0041_8193; u_pipe_cpu.imem.mem[9] = 32'h0041_8193;
            // Word 10(0x28): addi x2, x2, 1   (i = i + 1)
            u_single_cpu.imem.mem[10] = 32'h0011_0113; u_pipe_cpu.imem.mem[10] = 32'h0011_0113;
            // Word 11(0x2C): blt  x2, x1, -24 (if i < 4 branch back to Word 5 at 0x14)
            u_single_cpu.imem.mem[11] = 32'hFE11_44E3; u_pipe_cpu.imem.mem[11] = 32'hFE11_44E3;

            // Loop Exit:
            // Word 12(0x30): sw   x4, 40(x0)  (Mem[10] <= sum = 118)
            u_single_cpu.imem.mem[12] = 32'h0240_2423; u_pipe_cpu.imem.mem[12] = 32'h0240_2423;
            // Word 13(0x34): sw   x5, 44(x0)  (Mem[11] <= max = 45)
            u_single_cpu.imem.mem[13] = 32'h0250_2623; u_pipe_cpu.imem.mem[13] = 32'h0250_2623;
            // Word 14(0x38): beq  x0, x0, 0   (Halt self-loop)
            u_single_cpu.imem.mem[14] = 32'h0000_0063; u_pipe_cpu.imem.mem[14] = 32'h0000_0063;

            // --- 1. Run Single-Cycle CPU ---
            rst_n_single = 1'b0;
            repeat (2) @(posedge clk);
            #1; rst_n_single = 1'b1;

            single_cycles = 0;
            while ((u_single_cpu.pc_out !== halt_pc) && (single_cycles < 200)) begin
                @(posedge clk);
                single_cycles++;
            end

            // --- 2. Run Pipelined CPU ---
            rst_n_pipe = 1'b0;
            repeat (2) @(posedge clk);
            #1; rst_n_pipe = 1'b1;

            pipe_cycles    = 0;
            stall_cnt      = 0;
            flush_cnt      = 0;
            fwd_ex_mem_cnt = 0;
            fwd_mem_wb_cnt = 0;

            while ((u_pipe_cpu.pipe_mem_wb.wb_pc !== halt_pc) && (pipe_cycles < 200)) begin
                @(posedge clk);
                pipe_cycles++;

                if (u_pipe_cpu.load_use_hazard)
                    stall_cnt++;
                if (u_pipe_cpu.ex_redirect && (u_pipe_cpu.ex_pc !== halt_pc))
                    flush_cnt += 2;
                if (u_pipe_cpu.forward_a == 2'b10 || u_pipe_cpu.forward_b == 2'b10)
                    fwd_ex_mem_cnt++;
                if (u_pipe_cpu.forward_a == 2'b01 || u_pipe_cpu.forward_b == 2'b01)
                    fwd_mem_wb_cnt++;
            end

            verify_equivalence(bench_name[idx], match);

            // Explicit assertions for composite workload algorithm correctness
            if (u_single_cpu.reg_file.regs[4] !== 32'd118 || u_pipe_cpu.reg_file.regs[4] !== 32'd118) begin
                $display("  [ERROR] Composite sum assertion failed: Single=%0d, Pipe=%0d, Expected=118",
                         u_single_cpu.reg_file.regs[4], u_pipe_cpu.reg_file.regs[4]);
                match = 1'b0;
            end else begin
                $display("  [ASSERTION PASSED] Composite final sum is 118 across both cores.");
            end

            if (u_single_cpu.reg_file.regs[5] !== 32'd45 || u_pipe_cpu.reg_file.regs[5] !== 32'd45) begin
                $display("  [ERROR] Composite max assertion failed: Single=%0d, Pipe=%0d, Expected=45",
                         u_single_cpu.reg_file.regs[5], u_pipe_cpu.reg_file.regs[5]);
                match = 1'b0;
            end else begin
                $display("  [ASSERTION PASSED] Composite final max is 45 across both cores.");
            end

            if (u_single_cpu.reg_file.regs[2] !== 32'd4 || u_pipe_cpu.reg_file.regs[2] !== 32'd4) begin
                $display("  [ERROR] Composite index assertion failed: Single=%0d, Pipe=%0d, Expected=4",
                         u_single_cpu.reg_file.regs[2], u_pipe_cpu.reg_file.regs[2]);
                match = 1'b0;
            end else begin
                $display("  [ASSERTION PASSED] Composite final loop index is 4 across both cores.");
            end

            if (u_single_cpu.dmem.mem[10] !== 32'd118 || u_pipe_cpu.dmem.mem[10] !== 32'd118 ||
                u_single_cpu.dmem.mem[11] !== 32'd45  || u_pipe_cpu.dmem.mem[11] !== 32'd45) begin
                $display("  [ERROR] Composite stored memory assertion failed: Mem[10]=%0d, Mem[11]=%0d",
                         u_pipe_cpu.dmem.mem[10], u_pipe_cpu.dmem.mem[11]);
                match = 1'b0;
            end else begin
                $display("  [ASSERTION PASSED] Composite stored memory holds Mem[10]=118, Mem[11]=45 across both cores.");
            end

            inst_count[idx]       = single_cycles; // 34 dynamic instructions
            cycles_single[idx]    = single_cycles;
            cycles_pipe[idx]      = pipe_cycles;
            cpi_single[idx]       = real'(single_cycles) / real'(single_cycles);
            cpi_pipe[idx]         = real'(pipe_cycles) / real'(single_cycles);
            speedup_cycle[idx]    = real'(single_cycles) / real'(pipe_cycles);
            fill_cycles[idx]      = 4;
            stall_cycles[idx]     = stall_cnt;
            flush_cycles[idx]     = flush_cnt;
            fwd_ex_mem_count[idx] = fwd_ex_mem_cnt;
            fwd_mem_wb_count[idx] = fwd_mem_wb_cnt;
            state_match[idx]      = match;
        end
    endtask

    // =========================================================================
    // Main Benchmark Suite Execution
    // =========================================================================
    initial begin
        $dumpfile("sim/benchmark.vcd");
        $dumpvars(0, tb_benchmark);

        $display("\n==========================================================================================================");
        $display("   STAGE 10F — RV32I COMPARATIVE PERFORMANCE BENCHMARK SUITE");
        $display("   Single-Cycle CPU vs. 5-Stage Pipelined CPU (IF -> ID -> EX -> MEM -> WB)");
        $display("==========================================================================================================\n");

        run_benchmark_alu(0);
        run_benchmark_mem(1);
        run_benchmark_branch(2);
        run_benchmark_composite(3);

        // ---------------------------------------------------------------------
        // Formatted Comparative Report Table
        // ---------------------------------------------------------------------
        $display("\n==========================================================================================================");
        $display("                                PERFORMANCE BENCHMARK SUMMARY TABLE");
        $display("==========================================================================================================");
        $display("%-40s | %-6s | %-10s | %-10s | %-10s | %-10s | %-10s | %-6s",
                 "Workload Description", "Instrs", "Single Cyc", "Pipe Cyc", "CPI Single", "CPI Pipe", "Cycle Spdup", "Match?");
        $display("----------------------------------------------------------------------------------------------------------");

        total_benchmarks_passed = 0;
        for (int i = 0; i < 4; i++) begin
            $display("%-40s | %6d | %10d | %10d | %10.3f | %10.3f | %10.3fx | %-6s",
                     bench_name[i],
                     inst_count[i],
                     cycles_single[i],
                     cycles_pipe[i],
                     cpi_single[i],
                     cpi_pipe[i],
                     speedup_cycle[i],
                     (state_match[i] ? "PASS" : "FAIL"));
            if (state_match[i])
                total_benchmarks_passed++;
        end
        $display("==========================================================================================================");

        $display("\n==========================================================================================================");
        $display("                            DETAILED PIPELINE OVERHEAD & PENALTY BREAKDOWN");
        $display("==========================================================================================================");
        $display("%-40s | %-9s | %-12s | %-12s | %-12s | %-12s",
                 "Workload Description", "Fill Cyc", "Stall Cyc", "Flush Penalty", "EX/MEM Fwds", "MEM/WB Fwds");
        $display("----------------------------------------------------------------------------------------------------------");
        for (int i = 0; i < 4; i++) begin
            $display("%-40s | %9d | %12d | %12d | %12d | %12d",
                     bench_name[i],
                     fill_cycles[i],
                     stall_cycles[i],
                     flush_cycles[i],
                     fwd_ex_mem_count[i],
                     fwd_mem_wb_count[i]);
        end
        $display("==========================================================================================================\n");

        if (total_benchmarks_passed == 4) begin
            $display(">>> ALL 4/4 COMPARATIVE PERFORMANCE BENCHMARKS PASSED WITH FULL ARCHITECTURAL EQUIVALENCE! <<<\n");
            $finish(0);
        end else begin
            $fatal(1, "Benchmark failure: Architectural mismatch detected between single-cycle and pipelined cores.");
        end
    end

endmodule
