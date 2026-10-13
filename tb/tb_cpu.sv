`timescale 1ns / 1ps

// =============================================================================
// Module: tb_cpu
// Project: RV32I RISC-V Processor (Stage 9B Extension)
// Description:
//   Self-checking integrated testbench for the single-cycle RV32I CPU.
//   Verifies the complete base RV32I integer instruction set:
//     - Stage 8B Baseline (16 tests): ADDI, ADD, SUB, AND, OR, XOR, SW, LW,
//       BEQ, BNE, LUI, AUIPC, JAL, JALR, x0 write immunity, completion marker.
//     - Stage 9B Extensions (13 tests):
//       * R-type shifts & comparisons: SLL, SRL, SRA, SLT, SLTU (including shamt=31).
//       * I-type shifts & comparisons: SLLI, SRLI, SRAI, SLTI, SLTIU (including shamt=31).
//       * Full branch coverage: BLT, BGE, BLTU, BGEU (both taken and not-taken,
//         with verification that skipped trap instructions never execute).
// =============================================================================

module tb_cpu;

    // Simulation Clock and Reset
    logic clk;
    logic rst_n;

    // CPU Probes
    logic [31:0] pc_out;
    logic [31:0] instr_out;

    // Test Tracking
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;
    int cycles     = 0;

    // Instantiate CPU Top Module
    cpu u_cpu (
        .clk(clk),
        .rst_n(rst_n),
        .pc_out(pc_out),
        .instr_out(instr_out)
    );

    // 100 MHz System Clock (10ns period)
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Helper checking task for register state
    task check_reg(
        input string       test_name,
        input int          reg_idx,
        input logic [31:0] exp_val
    );
        logic [31:0] act_val;
        begin
            test_count++;
            act_val = u_cpu.reg_file.regs[reg_idx];

            if (act_val === exp_val) begin
                pass_count++;
                $display("[PASS] Test %02d: %-46s | x%02d = 0x%08h",
                         test_count, test_name, reg_idx, act_val);
            end else begin
                fail_count++;
                $display("[FAIL] Test %02d: %s | x%02d", test_count, test_name, reg_idx);
                $display("       Expected: 0x%08h", exp_val);
                $display("       Actual:   0x%08h", act_val);
            end
        end
    endtask

    // Helper checking task for data memory state
    task check_dmem(
        input string       test_name,
        input int          word_idx,
        input logic [31:0] exp_val
    );
        logic [31:0] act_val;
        begin
            test_count++;
            act_val = u_cpu.dmem.mem[word_idx];

            if (act_val === exp_val) begin
                pass_count++;
                $display("[PASS] Test %02d: %-46s | Mem[%0d] = 0x%08h",
                         test_count, test_name, word_idx, act_val);
            end else begin
                fail_count++;
                $display("[FAIL] Test %02d: %s | Mem[%0d]", test_count, test_name, word_idx);
                $display("       Expected: 0x%08h", exp_val);
                $display("       Actual:   0x%08h", act_val);
            end
        end
    endtask

    // Main Test Stimulus
    initial begin
        // Configure waveform dump
        $dumpfile("sim/cpu.vcd");
        $dumpvars(0, tb_cpu);

        $display("==========================================================================================");
        $display("   RV32I Single-Cycle CPU Full Integer Verification Testbench Started");
        $display("==========================================================================================");

        // ---------------------------------------------------------------------
        // PART 1: Stage 8B Test Program (Words 0 to 27)
        // ---------------------------------------------------------------------
        // Word 0 (0x00): addi x1, x0, 10
        u_cpu.imem.mem[0]  = 32'h00A0_0093;

        // Word 1 (0x04): addi x2, x0, 25
        u_cpu.imem.mem[1]  = 32'h0190_0113;

        // Word 2 (0x08): add x3, x1, x2  (10 + 25 = 35)
        u_cpu.imem.mem[2]  = 32'h0020_81B3;

        // Word 3 (0x0C): sub x4, x2, x1  (25 - 10 = 15)
        u_cpu.imem.mem[3]  = 32'h4011_0233;

        // Word 4 (0x10): and x5, x1, x2  (10 & 25 = 8)
        u_cpu.imem.mem[4]  = 32'h0020_F2B3;

        // Word 5 (0x14): or  x6, x1, x2  (10 | 25 = 27)
        u_cpu.imem.mem[5]  = 32'h0020_E333;

        // Word 6 (0x18): xor x7, x1, x2  (10 ^ 25 = 19)
        u_cpu.imem.mem[6]  = 32'h0020_C3B3;

        // Word 7 (0x1C): addi x0, x0, 99 (attempt write to x0; must remain 0)
        u_cpu.imem.mem[7]  = 32'h0630_0013;

        // Word 8 (0x20): sw x3, 8(x0)    (store x3=35 to Mem[8])
        u_cpu.imem.mem[8]  = 32'h0030_2423;

        // Word 9 (0x24): lw x8, 8(x0)    (load from Mem[8] into x8)
        u_cpu.imem.mem[9]  = 32'h0080_2403;

        // Word 10 (0x28): beq x1, x2, +8 (not taken; 10 != 25)
        u_cpu.imem.mem[10] = 32'h0020_8463;

        // Word 11 (0x2C): addi x9, x0, 1 (fall-through; proves non-taken advance to PC+4)
        u_cpu.imem.mem[11] = 32'h0010_0493;

        // Word 12 (0x30): beq x1, x1, +12 (taken! branches to Word 15 at 0x3C)
        u_cpu.imem.mem[12] = 32'h0010_8663;

        // Word 13 (0x34): [Trap] addi x9, x0, 99 (must be skipped)
        u_cpu.imem.mem[13] = 32'h0630_0493;

        // Word 14 (0x38): [Trap] addi x9, x0, 99 (must be skipped)
        u_cpu.imem.mem[14] = 32'h0630_0493;

        // Word 15 (0x3C): bne x1, x2, +12 (taken! branches to Word 18 at 0x48)
        u_cpu.imem.mem[15] = 32'h0020_9663;

        // Word 16 (0x40): [Trap] addi x9, x0, 88 (must be skipped)
        u_cpu.imem.mem[16] = 32'h0580_0493;

        // Word 17 (0x44): [Trap] addi x9, x0, 88 (must be skipped)
        u_cpu.imem.mem[17] = 32'h0580_0493;

        // Word 18 (0x48): lui x10, 0x12345 (x10 = 0x12345000)
        u_cpu.imem.mem[18] = 32'h1234_5537;

        // Word 19 (0x4C): auipc x11, 0x00010 (x11 = 0x4C + 0x10000 = 0x0001004C)
        u_cpu.imem.mem[19] = 32'h0001_0597;

        // Word 20 (0x50): jal x12, +12 (writes x12 = 0x54, jumps to Word 23 at 0x5C)
        u_cpu.imem.mem[20] = 32'h00C0_066F;

        // Word 21 (0x54): [Trap] addi x9, x0, 77 (must be skipped)
        u_cpu.imem.mem[21] = 32'h04D0_0493;

        // Word 22 (0x58): [Trap] addi x9, x0, 77 (must be skipped)
        u_cpu.imem.mem[22] = 32'h04D0_0493;

        // Word 23 (0x5C): addi x14, x0, 0x06D (setup odd address x14 = 0x6D)
        u_cpu.imem.mem[23] = 32'h06D0_0713;

        // Word 24 (0x60): jalr x13, 0(x14) (writes x13=0x64, jumps to 0x6D & ~1 = 0x6C)
        u_cpu.imem.mem[24] = 32'h0007_06E7;

        // Word 25 (0x64): [Trap] addi x9, x0, 66 (must be skipped)
        u_cpu.imem.mem[25] = 32'h0420_0493;

        // Word 26 (0x68): [Trap] addi x9, x0, 66 (must be skipped)
        u_cpu.imem.mem[26] = 32'h0420_0493;

        // Word 27 (0x6C): addi x15, x0, 1 (execution completion flag for Part 1: x15 = 1)
        u_cpu.imem.mem[27] = 32'h0010_0793;

        // ---------------------------------------------------------------------
        // PART 2: Stage 9B Extensions (Words 28 to 79)
        // ---------------------------------------------------------------------
        // Word 28 (0x70): addi x16, x0, 1 (x16 = 1)
        u_cpu.imem.mem[28] = 32'h0010_0813;

        // Word 29 (0x74): lui x17, 0x80000 (x17 = 0x80000000: negative MSB boundary)
        u_cpu.imem.mem[29] = 32'h8000_08B7;

        // Word 30 (0x78): addi x18, x0, -10 (x18 = -10 = 0xFFFFFFF6)
        u_cpu.imem.mem[30] = 32'hFF60_0913;

        // Word 31 (0x7C): addi x19, x0, 20 (x19 = +20 = 0x00000014)
        u_cpu.imem.mem[31] = 32'h0140_0993;

        // Word 32 (0x80): addi x20, x0, 4 (x20 = 4)
        u_cpu.imem.mem[32] = 32'h0040_0A13;

        // Word 33 (0x84): addi x21, x0, 31 (x21 = 31: maximum shift amount)
        u_cpu.imem.mem[33] = 32'h01F0_0A93;

        // --- R-type Operations ---
        // Word 34 (0x88): sll x22, x16, x20 (x22 = 1 << 4 = 16 = 0x10)
        u_cpu.imem.mem[34] = 32'h0148_1B33;

        // Word 35 (0x8C): srl x23, x17, x20 (x23 = 0x80000000 >> 4 = 0x08000000)
        u_cpu.imem.mem[35] = 32'h0148_DBB3;

        // Word 36 (0x90): sra x24, x17, x20 (x24 = 0x80000000 >>> 4 = 0xF8000000)
        u_cpu.imem.mem[36] = 32'h4148_DC33;

        // Word 37 (0x94): slt x25, x18, x19 (signed: -10 < 20 is true -> x25 = 1)
        u_cpu.imem.mem[37] = 32'h0139_2CB3;

        // Word 38 (0x98): sltu x26, x18, x19 (unsigned: 0xFFFFFFF6 < 20 is false -> x26 = 0)
        u_cpu.imem.mem[38] = 32'h0139_3D33;

        // Word 39 (0x9C): sll x27, x16, x21 (boundary shift 31: 1 << 31 = 0x80000000)
        u_cpu.imem.mem[39] = 32'h0158_1DB3;

        // --- I-type Operations ---
        // Word 40 (0xA0): slli x28, x16, 3 (x28 = 1 << 3 = 8)
        u_cpu.imem.mem[40] = 32'h0038_1E13;

        // Word 41 (0xA4): srli x29, x17, 31 (boundary shift 31: 0x80000000 >> 31 = 1)
        u_cpu.imem.mem[41] = 32'h01F8_DE93;

        // Word 42 (0xA8): srai x30, x17, 31 (boundary sign shift 31: 0x80000000 >>> 31 = 0xFFFFFFFF)
        u_cpu.imem.mem[42] = 32'h41F8_DF13;

        // Word 43 (0xAC): slti x31, x18, 0 (signed: -10 < 0 is true -> x31 = 1)
        u_cpu.imem.mem[43] = 32'h0009_2F93;

        // Word 44 (0xB0): sltiu x16, x19, 50 (unsigned: 20 < 50 is true -> x16 = 1)
        u_cpu.imem.mem[44] = 32'h0329_B813;

        // --- Branch Operations (using x17 as 8-bit pass/fail accumulator) ---
        // Word 45 (0xB4): addi x17, x0, 0 (reset accumulator to 0)
        u_cpu.imem.mem[45] = 32'h0000_0893;

        // 1. BLT Taken (-10 < 20 is true): branch to Word 49 (0xC4)
        u_cpu.imem.mem[46] = 32'h0139_4663; // blt x18, x19, +12
        u_cpu.imem.mem[47] = 32'h0630_0893; // [Trap] addi x17, x0, 99
        u_cpu.imem.mem[48] = 32'h0630_0893; // [Trap] addi x17, x0, 99
        u_cpu.imem.mem[49] = 32'h0018_8893; // Target: addi x17, x17, 1 (x17 = 1)

        // 2. BLT Not-Taken (20 < -10 is false): fall through to Word 51 (0xCC)
        u_cpu.imem.mem[50] = 32'h0129_C663; // blt x19, x18, +12
        u_cpu.imem.mem[51] = 32'h0028_8893; // addi x17, x17, 2 (x17 = 3)
        u_cpu.imem.mem[52] = 32'h0080_006F; // jal x0, +8 (skip trap to Word 54 at 0xD8)
        u_cpu.imem.mem[53] = 32'h0630_0893; // [Trap] addi x17, x0, 99

        // 3. BGE Taken (20 >= -10 is true): branch to Word 57 (0xE4)
        u_cpu.imem.mem[54] = 32'h0129_D663; // bge x19, x18, +12
        u_cpu.imem.mem[55] = 32'h0630_0893; // [Trap] addi x17, x0, 99
        u_cpu.imem.mem[56] = 32'h0630_0893; // [Trap] addi x17, x0, 99
        u_cpu.imem.mem[57] = 32'h0048_8893; // Target: addi x17, x17, 4 (x17 = 7)

        // 4. BGE Not-Taken (-10 >= 20 is false): fall through to Word 59 (0xEC)
        u_cpu.imem.mem[58] = 32'h0139_5663; // bge x18, x19, +12
        u_cpu.imem.mem[59] = 32'h0088_8893; // addi x17, x17, 8 (x17 = 15)
        u_cpu.imem.mem[60] = 32'h0080_006F; // jal x0, +8 (skip trap to Word 62 at 0xF8)
        u_cpu.imem.mem[61] = 32'h0630_0893; // [Trap] addi x17, x0, 99

        // 5. BLTU Taken (20 < 0xFFFFFFF6 is true): branch to Word 65 (0x104)
        u_cpu.imem.mem[62] = 32'h0129_E663; // bltu x19, x18, +12
        u_cpu.imem.mem[63] = 32'h0630_0893; // [Trap] addi x17, x0, 99
        u_cpu.imem.mem[64] = 32'h0630_0893; // [Trap] addi x17, x0, 99
        u_cpu.imem.mem[65] = 32'h0108_8893; // Target: addi x17, x17, 16 (x17 = 31)

        // 6. BLTU Not-Taken (0xFFFFFFF6 < 20 is false): fall through to Word 67 (0x10C)
        u_cpu.imem.mem[66] = 32'h0139_6663; // bltu x18, x19, +12
        u_cpu.imem.mem[67] = 32'h0208_8893; // addi x17, x17, 32 (x17 = 63)
        u_cpu.imem.mem[68] = 32'h0080_006F; // jal x0, +8 (skip trap to Word 70 at 0x118)
        u_cpu.imem.mem[69] = 32'h0630_0893; // [Trap] addi x17, x0, 99

        // 7. BGEU Taken (0xFFFFFFF6 >= 20 is true): branch to Word 73 (0x124)
        u_cpu.imem.mem[70] = 32'h0139_7663; // bgeu x18, x19, +12
        u_cpu.imem.mem[71] = 32'h0630_0893; // [Trap] addi x17, x0, 99
        u_cpu.imem.mem[72] = 32'h0630_0893; // [Trap] addi x17, x0, 99
        u_cpu.imem.mem[73] = 32'h0408_8893; // Target: addi x17, x17, 64 (x17 = 127)

        // 8. BGEU Not-Taken (20 >= 0xFFFFFFF6 is false): fall through to Word 75 (0x12C)
        u_cpu.imem.mem[74] = 32'h0129_F663; // bgeu x19, x18, +12
        u_cpu.imem.mem[75] = 32'h0808_8893; // addi x17, x17, 128 (x17 = 255 = 0xFF)
        u_cpu.imem.mem[76] = 32'h0080_006F; // jal x0, +8 (skip trap to Word 78 at 0x138)
        u_cpu.imem.mem[77] = 32'h0630_0893; // [Trap] addi x17, x0, 99

        // Final Stage 9B Marker & Halt Loop
        // Word 78 (0x138): addi x20, x0, 90 (x20 = 90 = 0x5A)
        u_cpu.imem.mem[78] = 32'h05A0_0A13;

        // Word 79 (0x13C): beq x0, x0, 0 (terminal self-loop halt at 0x13C)
        u_cpu.imem.mem[79] = 32'h0000_0063;

        // ---------------------------------------------------------------------
        // Apply System Reset
        // ---------------------------------------------------------------------
        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        rst_n = 1'b1;

        // ---------------------------------------------------------------------
        // Watchdog Execution Monitor
        // Wait until PC reaches terminal self-loop at 0x13C, or timeout.
        // ---------------------------------------------------------------------
        begin : execution_monitor
            cycles = 0;
            while ((pc_out !== 32'h0000_013C) && (cycles < 200)) begin
                @(posedge clk);
                cycles++;
            end

            if (pc_out !== 32'h0000_013C) begin
                $display("[ERROR] Watchdog timeout: PC failed to reach terminal halt at 0x13C! Current PC = 0x%08h", pc_out);
                $fatal(1, "CPU execution timed out.");
            end else begin
                $display(">>> CPU reached terminal halt at PC=0x%08h in %0d cycles <<<", pc_out, cycles);
            end
        end

        // Settle one additional cycle in self-loop
        repeat (2) @(posedge clk);
        #1;

        // ---------------------------------------------------------------------
        // Verification: Section 1 — Stage 8B Regressions (16 Tests)
        // ---------------------------------------------------------------------
        $display("--- SECTION 1: Verifying Stage 8B Regression Suite (16 Tests) ---");

        check_reg("ADDI: x1 loaded with 10",
                  1, 32'd10);

        check_reg("ADDI: x2 loaded with 25",
                  2, 32'd25);

        check_reg("ADD: x3 = x1 + x2 = 35",
                  3, 32'd35);

        check_reg("SUB: x4 = x2 - x1 = 15",
                  4, 32'd15);

        check_reg("AND: x5 = x1 & x2 = 8",
                  5, 32'd8);

        check_reg("OR:  x6 = x1 | x2 = 27",
                  6, 32'd27);

        check_reg("XOR: x7 = x1 ^ x2 = 19",
                  7, 32'd19);

        check_dmem("SW: Data Memory at word 2 (addr 8) holds 35",
                   2, 32'd35);

        check_reg("LW: x8 loaded from Mem[8] holds 35",
                  8, 32'd35);

        check_reg("BEQ/BNE Control: Fall-through & traps skipped (x9=1)",
                  9, 32'd1);

        check_reg("LUI: x10 loaded with upper immediate 0x12345000",
                  10, 32'h1234_5000);

        check_reg("AUIPC: x11 = PC(0x4C) + 0x10000 = 0x0001004C",
                  11, 32'h0001_004C);

        check_reg("JAL: x12 holds return address PC+4 (0x54)",
                  12, 32'h0000_0054);

        check_reg("JALR: x13 holds return address PC+4 (0x64)",
                  13, 32'h0000_0064);

        check_reg("Zero Register: x0 strictly remains 0",
                  0, 32'h0000_0000);

        check_reg("Stage 8B Completion Flag: x15 set to 1",
                  15, 32'd1);

        // ---------------------------------------------------------------------
        // Verification: Section 2 — Stage 9B Extensions (13 Tests)
        // ---------------------------------------------------------------------
        $display("--- SECTION 2: Verifying Stage 9B Extensions (13 Tests) ---");

        // R-type Shifts & Comparisons
        check_reg("R-type SLL: x22 = 1 << 4 = 16",
                  22, 32'h0000_0010);

        check_reg("R-type SRL: x23 = 0x80000000 >> 4 = 0x08000000",
                  23, 32'h0800_0000);

        check_reg("R-type SRA: x24 = 0x80000000 >>> 4 = 0xF8000000",
                  24, 32'hF800_0000);

        check_reg("R-type SLT (signed): x25 = (-10 < 20) = 1",
                  25, 32'd1);

        check_reg("R-type SLTU (unsigned): x26 = (0xFFFFFFF6 < 20) = 0",
                  26, 32'd0);

        check_reg("R-type SLL Boundary shamt 31: x27 = 1 << 31 = 0x80000000",
                  27, 32'h8000_0000);

        // I-type Shifts & Comparisons
        check_reg("I-type SLLI: x28 = 1 << 3 = 8",
                  28, 32'h0000_0008);

        check_reg("I-type SRLI Boundary shamt 31: x29 = 0x80000000 >> 31 = 1",
                  29, 32'h0000_0001);

        check_reg("I-type SRAI Boundary shamt 31: x30 = 0x80000000 >>> 31 = 0xFFFFFFFF",
                  30, 32'hFFFF_FFFF);

        check_reg("I-type SLTI (signed): x31 = (-10 < 0) = 1",
                  31, 32'd1);

        check_reg("I-type SLTIU (unsigned): x16 = (20 < 50) = 1",
                  16, 32'd1);

        // Branch Operations (8-bit verification accumulator x17)
        check_reg("Branch Suite (BLT/BGE/BLTU/BGEU, taken/not-taken, traps skipped)",
                  17, 32'h0000_00FF);

        // Stage 9B Marker
        check_reg("Stage 9B Completion Flag: x20 set to 90 (0x5A)",
                  20, 32'h0000_005A);

        // ---------------------------------------------------------------------
        // Final Summary & Exit
        // ---------------------------------------------------------------------
        $display("==========================================================================================");
        $display("   RV32I Full Integer CPU Verification Summary: Total=%0d | Passed=%0d | Failed=%0d",
                 test_count, pass_count, fail_count);
        $display("==========================================================================================");

        if (fail_count == 0) begin
            $display(">>> ALL 29/29 RV32I INTEGRATED CPU TESTS PASSED SUCCESSFULLY! <<<");
            $finish(0);
        end else begin
            $display(">>> CPU TESTBENCH FAILED (%0d ERRORS) <<<", fail_count);
            $fatal(1, "Terminating due to verification failure.");
        end
    end

endmodule
