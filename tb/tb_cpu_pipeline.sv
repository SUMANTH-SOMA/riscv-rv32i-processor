`timescale 1ns / 1ps

// =============================================================================
// Module: tb_cpu_pipeline
// Project: RV32I RISC-V Processor (Stage 10D Extension)
// Description:
//   Self-checking verification testbench for the 5-Stage Pipelined RV32I CPU
//   with Data Forwarding and Load-Use Hazard Detection & Stalling.
//
// Test Coverage:
//   - Section 1: Reset Initialization Check (Tests 01-05).
//   - Section 2: Cycle-by-Cycle Pipeline Register Propagation (Tests 06-10).
//   - Section 3: Sequential Architectural Commits (Tests 11-15).
//   - Section 4: Memory Access & Metadata Preservation (Tests 16-19).
//   - Section 5: Deterministic Bubble Movement (Tests 20-21).
//   - Section 6: Stage 10C Data Forwarding Directed Tests (Tests 22-31):
//       * EX/MEM-to-EX Operand A & B forwarding.
//       * MEM/WB-to-EX Operand A & B forwarding.
//       * EX/MEM priority over MEM/WB.
//       * Store-data forwarding from EX/MEM and MEM/WB.
//       * WB-to-ID internal bypass.
//       * Zero register (x0) forwarding immunity.
//   - Section 7: Stage 10D Load-Use Hazard Detection & Stalling Suite (Tests 32-42):
//       * Test 32: Cycle-accurate detection of load-use hazard condition.
//       * Test 33: Pipeline stall controls active (stall_pc, stall_if_id, flush_id_ex).
//       * Test 34: Cycle-accurate verification that IF/ID instruction is held at PC=0x04.
//       * Test 35: Cycle-accurate verification of ID/EX NOP bubble injection.
//       * Test 36: Exact 1-cycle stall recovery (hazard deasserts after 1 cycle).
//       * Test 37: Load-to-ALU Operand A result (lw x1 -> addi x2, x1, 25 = 525).
//       * Test 38: Load-to-ALU Operand B result (lw x3 -> sub x4, x0, x3 = -777).
//       * Test 39: Load-to-Store data forwarding with 1 stall (lw x5 -> sw x5 = 500).
//       * Test 40: Load-to-Branch stall and safe sequential execution (x7 = 88).
//       * Test 41: Load to x0 does not trigger false stall (x8 = 99).
//       * Test 42: Immediate matching load rd does not trigger false rs2 stall (x9 = 20).
// =============================================================================

module tb_cpu_pipeline;

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

    // Instantiate Pipelined CPU Top Module
    cpu_pipeline u_cpu (
        .clk(clk),
        .rst_n(rst_n),
        .pc_out(pc_out),
        .instr_out(instr_out)
    );

    // 100 MHz System Clock (10ns period)
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Cycle counter
    always @(posedge clk) begin
        cycles++;
    end

    // Generic Assertion Task
    task assert_true(
        input string test_name,
        input logic  condition,
        input string actual_info
    );
        begin
            test_count++;
            if (condition) begin
                pass_count++;
                $display("[PASS] Test %02d: %-58s | %s", test_count, test_name, actual_info);
            end else begin
                fail_count++;
                $display("[FAIL] Test %02d: %-58s | %s", test_count, test_name, actual_info);
            end
        end
    endtask

    // Register Verification Task
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
                $display("[PASS] Test %02d: %-58s | x%02d = 0x%08h (%0d)",
                         test_count, test_name, reg_idx, act_val, $signed(act_val));
            end else begin
                fail_count++;
                $display("[FAIL] Test %02d: %s | x%02d (Expected: 0x%08h, Actual: 0x%08h)",
                         test_count, test_name, reg_idx, exp_val, act_val);
            end
        end
    endtask

    // Data Memory Verification Task
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
                $display("[PASS] Test %02d: %-58s | Mem[%0d] = 0x%08h (%0d)",
                         test_count, test_name, word_idx, act_val, $signed(act_val));
            end else begin
                fail_count++;
                $display("[FAIL] Test %02d: %s | Mem[%0d] (Expected: 0x%08h, Actual: 0x%08h)",
                         test_count, test_name, word_idx, exp_val, act_val);
            end
        end
    endtask

    // Canonical NOP
    localparam logic [31:0] NOP_INSTR = 32'h0000_0013; // addi x0, x0, 0

    // Test Stimulus
    initial begin
        // Configure Waveform Dump
        $dumpfile("sim/cpu_pipeline.vcd");
        $dumpvars(0, tb_cpu_pipeline);

        $display("==========================================================================================");
        $display("   RV32I 5-Stage Pipelined CPU (Stage 10D Load-Use Stalling) Verification Started");
        $display("==========================================================================================");

        // =====================================================================
        // PART 1: Baseline Stages 10B & 10C Verification Suite (Tests 01-31)
        // =====================================================================
        // Word 0 (0x00): addi x1, x0, 10
        u_cpu.imem.mem[0]  = 32'h00A0_0093;
        // Word 1 (0x04): addi x2, x0, 25
        u_cpu.imem.mem[1]  = 32'h0190_0113;
        // Word 2 (0x08): lui  x3, 0x12345
        u_cpu.imem.mem[2]  = 32'h1234_51B7;
        // Word 3 (0x0C): addi x4, x0, -5
        u_cpu.imem.mem[3]  = 32'hFFB0_0213;
        // Word 4 (0x10): addi x0, x0, 99
        u_cpu.imem.mem[4]  = 32'h0630_0013;
        // Word 5 (0x14): sw   x1, 16(x0)
        u_cpu.imem.mem[5]  = 32'h0010_2823;
        // Word 6 (0x18): NOP
        u_cpu.imem.mem[6]  = NOP_INSTR;
        // Word 7 (0x1C): NOP
        u_cpu.imem.mem[7]  = NOP_INSTR;
        // Word 8 (0x20): lw   x5, 16(x0)
        u_cpu.imem.mem[8]  = 32'h0100_2283;
        // Word 9 (0x24): NOP
        u_cpu.imem.mem[9]  = NOP_INSTR;
        // Word 10(0x28): NOP
        u_cpu.imem.mem[10] = NOP_INSTR;
        // Word 11(0x2C): addi x7, x0, 77
        u_cpu.imem.mem[11] = 32'h04D0_0393;

        // Stage 10C Forwarding Directed Instructions
        // Word 12 (0x30): addi x10, x0, 100
        u_cpu.imem.mem[12] = 32'h0640_0513;
        // Word 13 (0x34): addi x11, x10, 5       -> x11 = 105 (EX/MEM to EX Op A)
        u_cpu.imem.mem[13] = 32'h0055_0593;
        // Word 14 (0x38): addi x12, x0, 50
        u_cpu.imem.mem[14] = 32'h0320_0613;
        // Word 15 (0x3C): add  x13, x0, x12      -> x13 = 50  (EX/MEM to EX Op B)
        u_cpu.imem.mem[15] = 32'h00C0_06B3;
        // Word 16 (0x40): addi x14, x0, 200
        u_cpu.imem.mem[16] = 32'h0C80_0713;
        // Word 17 (0x44): NOP
        u_cpu.imem.mem[17] = NOP_INSTR;
        // Word 18 (0x48): addi x15, x14, 10      -> x15 = 210 (MEM/WB to EX Op A)
        u_cpu.imem.mem[18] = 32'h00A7_0793;
        // Word 19 (0x4C): addi x16, x0, 30
        u_cpu.imem.mem[19] = 32'h01E0_0813;
        // Word 20 (0x50): NOP
        u_cpu.imem.mem[20] = NOP_INSTR;
        // Word 21 (0x54): add  x17, x0, x16      -> x17 = 30  (MEM/WB to EX Op B)
        u_cpu.imem.mem[21] = 32'h0100_08B3;
        // Word 22 (0x58): addi x18, x0, 1
        u_cpu.imem.mem[22] = 32'h0010_0913;
        // Word 23 (0x5C): addi x18, x0, 2
        u_cpu.imem.mem[23] = 32'h0020_0913;
        // Word 24 (0x60): addi x19, x18, 10      -> x19 = 12  (Priority EX/MEM over MEM/WB)
        u_cpu.imem.mem[24] = 32'h00A9_0993;
        // Word 25 (0x64): addi x20, x0, 42
        u_cpu.imem.mem[25] = 32'h02A0_0A13;
        // Word 26 (0x68): sw   x20, 32(x0)       -> Mem[8] = 42 (Store-Data EX/MEM)
        u_cpu.imem.mem[26] = 32'h0340_2023;
        // Word 27 (0x6C): addi x21, x0, 84
        u_cpu.imem.mem[27] = 32'h0540_0A93;
        // Word 28 (0x70): NOP
        u_cpu.imem.mem[28] = NOP_INSTR;
        // Word 29 (0x74): sw   x21, 36(x0)       -> Mem[9] = 84 (Store-Data MEM/WB)
        u_cpu.imem.mem[29] = 32'h0350_2223;
        // Word 30 (0x78): addi x22, x0, 999
        u_cpu.imem.mem[30] = 32'h3E70_0B13;
        // Word 31 (0x7C): NOP
        u_cpu.imem.mem[31] = NOP_INSTR;
        // Word 32 (0x80): NOP
        u_cpu.imem.mem[32] = NOP_INSTR;
        // Word 33 (0x84): addi x23, x22, 1       -> x23 = 1000 (WB-to-ID bypass)
        u_cpu.imem.mem[33] = 32'h001B_0B93;
        // Word 34 (0x88): addi x0, x0, 1234
        u_cpu.imem.mem[34] = 32'h4D20_0013;
        // Word 35 (0x8C): addi x24, x0, 7        -> x24 = 7   (x0 immunity)
        u_cpu.imem.mem[35] = 32'h0070_0C13;

        // ---------------------------------------------------------------------
        // SECTION 1: Reset Initialization Check
        // ---------------------------------------------------------------------
        $display("--- SECTION 1: Reset Initialization Check ---");
        rst_n = 1'b0;
        #20;

        assert_true("Reset: IF stage PC is 0x00000000",
                    (u_cpu.if_pc === 32'h0000_0000),
                    $sformatf("if_pc = 0x%08h", u_cpu.if_pc));

        assert_true("Reset: IF/ID register holds NOP bubble",
                    (u_cpu.pipe_if_id.id_instr === NOP_INSTR && u_cpu.pipe_if_id.id_pc === 32'h0),
                    $sformatf("id_instr = 0x%08h, id_pc = 0x%08h",
                              u_cpu.pipe_if_id.id_instr, u_cpu.pipe_if_id.id_pc));

        assert_true("Reset: ID/EX control signals are zeroed (bubble)",
                    (u_cpu.pipe_id_ex.ex_reg_write === 1'b0 &&
                     u_cpu.pipe_id_ex.ex_mem_read  === 1'b0 &&
                     u_cpu.pipe_id_ex.ex_mem_write === 1'b0),
                    $sformatf("ex_reg_write=%b, ex_mem_read=%b, ex_mem_write=%b",
                              u_cpu.pipe_id_ex.ex_reg_write,
                              u_cpu.pipe_id_ex.ex_mem_read,
                              u_cpu.pipe_id_ex.ex_mem_write));

        assert_true("Reset: EX/MEM control signals are zeroed (bubble)",
                    (u_cpu.pipe_ex_mem.mem_reg_write === 1'b0 &&
                     u_cpu.pipe_ex_mem.mem_mem_read  === 1'b0 &&
                     u_cpu.pipe_ex_mem.mem_mem_write === 1'b0),
                    $sformatf("mem_reg_write=%b, mem_mem_read=%b, mem_mem_write=%b",
                              u_cpu.pipe_ex_mem.mem_reg_write,
                              u_cpu.pipe_ex_mem.mem_mem_read,
                              u_cpu.pipe_ex_mem.mem_mem_write));

        assert_true("Reset: MEM/WB control signals are zeroed (bubble)",
                    (u_cpu.pipe_mem_wb.wb_reg_write === 1'b0 &&
                     u_cpu.pipe_mem_wb.wb_mem_to_reg === 1'b0),
                    $sformatf("wb_reg_write=%b, wb_mem_to_reg=%b",
                              u_cpu.pipe_mem_wb.wb_reg_write,
                              u_cpu.pipe_mem_wb.wb_mem_to_reg));

        // ---------------------------------------------------------------------
        // SECTION 2: Pipeline Propagation Across Clock Cycles
        // ---------------------------------------------------------------------
        $display("--- SECTION 2: Cycle-by-Cycle Pipeline Register Propagation ---");

        assert_true("Pre-Run: Word 0 presented in IF stage (PC=0x00)",
                    (u_cpu.if_pc === 32'h0000_0000 && u_cpu.if_instr === 32'h00A0_0093),
                    $sformatf("if_pc=0x%08h, if_instr=0x%08h", u_cpu.if_pc, u_cpu.if_instr));

        @(negedge clk);
        rst_n = 1'b1;

        @(posedge clk); #1;
        assert_true("Clock 1: Word 0 in ID (PC=0x00), Word 1 in IF (PC=0x04)",
                    (u_cpu.pipe_if_id.id_pc === 32'h0000_0000 &&
                     u_cpu.pipe_if_id.id_instr === 32'h00A0_0093 &&
                     u_cpu.if_pc === 32'h0000_0004 &&
                     u_cpu.if_instr === 32'h0190_0113),
                    $sformatf("ID: pc=0x%08h instr=0x%08h | IF: pc=0x%08h instr=0x%08h",
                              u_cpu.pipe_if_id.id_pc, u_cpu.pipe_if_id.id_instr,
                              u_cpu.if_pc, u_cpu.if_instr));

        @(posedge clk); #1;
        assert_true("Clock 2: Word 0 in EX (PC=0x00), Word 1 in ID (PC=0x04)",
                    (u_cpu.pipe_id_ex.ex_pc === 32'h0000_0000 &&
                     u_cpu.pipe_id_ex.ex_instr === 32'h00A0_0093 &&
                     u_cpu.pipe_id_ex.ex_rd === 5'd1 &&
                     u_cpu.pipe_if_id.id_pc === 32'h0000_0004),
                    $sformatf("EX: pc=0x%08h rd=%0d | ID: pc=0x%08h",
                              u_cpu.pipe_id_ex.ex_pc, u_cpu.pipe_id_ex.ex_rd,
                              u_cpu.pipe_if_id.id_pc));

        @(posedge clk); #1;
        assert_true("Clock 3: Word 0 in MEM (PC=0x00, alu_result=10), Word 1 in EX",
                    (u_cpu.pipe_ex_mem.mem_pc === 32'h0000_0000 &&
                     u_cpu.pipe_ex_mem.mem_alu_result === 32'd10 &&
                     u_cpu.pipe_ex_mem.mem_rd === 5'd1 &&
                     u_cpu.pipe_id_ex.ex_pc === 32'h0000_0004),
                    $sformatf("MEM: pc=0x%08h alu_result=%0d rd=%0d",
                              u_cpu.pipe_ex_mem.mem_pc,
                              u_cpu.pipe_ex_mem.mem_alu_result,
                              u_cpu.pipe_ex_mem.mem_rd));

        @(posedge clk); #1;
        assert_true("Clock 4: Word 0 in WB (PC=0x00, wb_data=10, reg_write=1)",
                    (u_cpu.pipe_mem_wb.wb_pc === 32'h0000_0000 &&
                     u_cpu.pipe_mem_wb.wb_alu_result === 32'd10 &&
                     u_cpu.pipe_mem_wb.wb_rd === 5'd1 &&
                     u_cpu.pipe_mem_wb.wb_reg_write === 1'b1),
                    $sformatf("WB: pc=0x%08h wb_alu_result=%0d rd=%0d reg_write=%b",
                              u_cpu.pipe_mem_wb.wb_pc,
                              u_cpu.pipe_mem_wb.wb_alu_result,
                              u_cpu.pipe_mem_wb.wb_rd,
                              u_cpu.pipe_mem_wb.wb_reg_write));

        // ---------------------------------------------------------------------
        // SECTION 3: Sequential Architectural Commit Verification
        // ---------------------------------------------------------------------
        $display("--- SECTION 3: Verifying Architectural Register File Commits ---");

        @(posedge clk); #1;
        check_reg("Word 0 Commit: x1 = 10", 1, 32'd10);

        @(posedge clk); #1;
        check_reg("Word 1 Commit: x2 = 25", 2, 32'd25);

        @(posedge clk); #1;
        check_reg("Word 2 Commit: LUI x3 = 0x12345000", 3, 32'h1234_5000);

        @(posedge clk); #1;
        check_reg("Word 3 Commit: x4 = 0xFFFFFFFB (-5)", 4, 32'hFFFF_FFFB);

        @(posedge clk); #1;
        check_reg("Word 4 Commit: Zero Register x0 immunity (remains 0)", 0, 32'd0);

        @(posedge clk); #1;
        check_dmem("Word 5 Commit: Mem[4] (addr 16) holds x1=10", 4, 32'd10);

        // ---------------------------------------------------------------------
        // SECTION 4: Memory Access & Metadata Preservation (SW & LW)
        // ---------------------------------------------------------------------
        $display("--- SECTION 4: Store & Load Execution + Metadata Preservation ---");

        @(posedge clk); #1;
        assert_true("Architectural Caution: MEM stage preserves mem_to_reg=1 for Load",
                    (u_cpu.pipe_ex_mem.mem_mem_to_reg === 1'b1 &&
                     u_cpu.pipe_ex_mem.mem_mem_read   === 1'b1 &&
                     u_cpu.pipe_ex_mem.mem_rd         === 5'd5),
                    $sformatf("mem_mem_to_reg=%b, mem_mem_read=%b, rd=%0d",
                              u_cpu.pipe_ex_mem.mem_mem_to_reg,
                              u_cpu.pipe_ex_mem.mem_mem_read,
                              u_cpu.pipe_ex_mem.mem_rd));

        @(posedge clk); #1;
        assert_true("Architectural Caution: WB stage preserves wb_mem_to_reg=1 for Load",
                    (u_cpu.pipe_mem_wb.wb_mem_to_reg    === 1'b1 &&
                     u_cpu.pipe_mem_wb.wb_mem_read_data === 32'd10 &&
                     u_cpu.pipe_mem_wb.wb_rd            === 5'd5),
                    $sformatf("wb_mem_to_reg=%b, wb_mem_read_data=%0d, wb_rd=%0d",
                              u_cpu.pipe_mem_wb.wb_mem_to_reg,
                              u_cpu.pipe_mem_wb.wb_mem_read_data,
                              u_cpu.pipe_mem_wb.wb_rd));

        @(posedge clk); #1;
        check_reg("Word 8 Commit: LW loaded x5 = 10 from Mem[4]", 5, 32'd10);

        repeat (3) @(posedge clk); #1;
        check_reg("Word 11 Commit: x7 = 77", 7, 32'd77);

        // ---------------------------------------------------------------------
        // SECTION 5: Deterministic Bubble Movement Verification
        // ---------------------------------------------------------------------
        $display("--- SECTION 5: Deterministic Bubble / NOP Movement ---");
        assert_true("NOP Execution: x0 remains zero during canonical NOP retirement",
                    (u_cpu.reg_file.regs[0] === 32'd0),
                    $sformatf("x0 = 0x%08h", u_cpu.reg_file.regs[0]));

        // ---------------------------------------------------------------------
        // SECTION 6: Stage 10C Data Forwarding Directed Tests
        // ---------------------------------------------------------------------
        $display("--- SECTION 6: Stage 10C Data Forwarding Directed Tests ---");
        repeat (28) @(posedge clk); #1;

        check_reg("Forward EX/MEM -> EX (Op A): x11 = 100 + 5 = 105", 11, 32'd105);
        check_reg("Forward EX/MEM -> EX (Op B): x13 = 0 + 50 = 50", 13, 32'd50);
        check_reg("Forward MEM/WB -> EX (Op A): x15 = 200 + 10 = 210", 15, 32'd210);
        check_reg("Forward MEM/WB -> EX (Op B): x17 = 0 + 30 = 30", 17, 32'd30);
        check_reg("Priority EX/MEM over MEM/WB: x19 = 2 + 10 = 12", 19, 32'd12);
        check_dmem("Store-Data Forwarding (EX/MEM): Mem[8] holds 42", 8, 32'd42);
        check_dmem("Store-Data Forwarding (MEM/WB): Mem[9] holds 84", 9, 32'd84);
        check_reg("WB-to-ID Internal Bypass: x23 = 999 + 1 = 1000", 23, 32'd1000);
        check_reg("Zero Register Immunity: x24 = 0 + 7 = 7 (no x0 fwd)", 24, 32'd7);
        check_reg("Hardwired x0 Integrity: x0 strictly remains 0", 0, 32'd0);

        // =====================================================================
        // PART 2: Stage 10D Load-Use Hazard Detection & Stalling Suite
        // =====================================================================
        $display("------------------------------------------------------------------------------------------");
        $display("--- SECTION 7: Stage 10D Load-Use Hazard Detection & Stalling Directed Tests ---");
        $display("------------------------------------------------------------------------------------------");

        // Step 1: Synchronous Reset & DUT Re-initialization
        rst_n = 1'b0;
        #20;

        // Clear architectural registers
        for (int i = 0; i < 32; i++) begin
            u_cpu.reg_file.regs[i] = 32'd0;
        end

        // Initialize Data Memory for Load-Use Tests
        u_cpu.dmem.mem[10] = 32'd500; // Byte address 40 (0x28)
        u_cpu.dmem.mem[11] = 32'd777; // Byte address 44 (0x2C)

        // Clear and Populate Instruction Memory for Load-Use Tests
        for (int i = 0; i < 64; i++) begin
            u_cpu.imem.mem[i] = NOP_INSTR;
        end

        // Test A: lw followed immediately by ALU instruction consuming rs1
        // Word 0 (0x00): lw   x1, 40(x0)        (0x02802083) -> x1 <= 500
        u_cpu.imem.mem[0]  = 32'h0280_2083;
        // Word 1 (0x04): addi x2, x1, 25        (0x01908113) -> x2 <= 525 (load-use hazard on rs1!)
        u_cpu.imem.mem[1]  = 32'h0190_8113;

        // Test B: lw followed immediately by ALU instruction consuming rs2
        // Word 2 (0x08): lw   x3, 44(x0)        (0x02C02183) -> x3 <= 777
        u_cpu.imem.mem[2]  = 32'h02C0_2183;
        // Word 3 (0x0C): sub  x4, x0, x3        (0x40300233) -> x4 <= -777 (load-use hazard on rs2!)
        u_cpu.imem.mem[3]  = 32'h4030_0233;

        // Test C: lw followed immediately by store consuming loaded value as store data
        // Word 4 (0x10): lw   x5, 40(x0)        (0x02802283) -> x5 <= 500
        u_cpu.imem.mem[4]  = 32'h0280_2283;
        // Word 5 (0x14): sw   x5, 48(x0)        (0x02502823) -> Mem[12] <= 500 (load-use on store data!)
        u_cpu.imem.mem[5]  = 32'h0250_2823;

        // Test D: lw followed immediately by branch consuming loaded value
        // Word 6 (0x18): lw   x6, 40(x0)        (0x02802303) -> x6 <= 500
        u_cpu.imem.mem[6]  = 32'h0280_2303;
        // Word 7 (0x1C): beq  x6, x0, 8         (0x00030463) -> not taken (500 != 0); tests branch stall!
        u_cpu.imem.mem[7]  = 32'h0003_0463;
        // Word 8 (0x20): addi x7, x0, 88        (0x05800393) -> x7 <= 88
        u_cpu.imem.mem[8]  = 32'h0580_0393;

        // Test E: Load to x0 must NOT trigger stall
        // Word 9 (0x24): lw   x0, 40(x0)        (0x02802003) -> target x0
        u_cpu.imem.mem[9]  = 32'h0280_2003;
        // Word 10(0x28): addi x8, x0, 99        (0x06300413) -> x8 <= 99 (no stall!)
        u_cpu.imem.mem[10] = 32'h0630_0413;

        // Test F: Immediate bits matching load rd must NOT trigger false rs2 stall
        // Word 11(0x2C): lw   x20, 40(x0)       (0x02802A03) -> rd = 20
        u_cpu.imem.mem[11] = 32'h0280_2A03;
        // Word 12(0x30): addi x9, x0, 20        (0x01400493) -> imm[4:0] = 20, but uses_rs2 = 0!
        u_cpu.imem.mem[12] = 32'h0140_0493;

        // Test H: Independent instructions sequence
        // Word 13(0x34): addi x25, x0, 1        (0x00100C93)
        u_cpu.imem.mem[13] = 32'h0010_0C93;
        // Word 14(0x38): addi x26, x0, 2        (0x00200D13)
        u_cpu.imem.mem[14] = 32'h0020_0D13;

        // Release reset synchronously
        @(negedge clk);
        rst_n = 1'b1;

        // Cycle 1: Word 0 in ID (PC=0x00); Word 1 in IF (PC=0x04)
        @(posedge clk); #1;

        // Cycle 2: Word 0 (lw x1) enters EX; Word 1 (addi x2, x1, 25) enters ID!
        // Hazard detection unit MUST detect load-use dependency immediately!
        @(posedge clk); #1;
        assert_true("Load-Use Detection: Hazard asserted for lw in EX and addi in ID",
                    (u_cpu.load_use_hazard === 1'b1),
                    $sformatf("load_use_hazard=%b (ex_rd=%0d, id_rs1=%0d)",
                              u_cpu.load_use_hazard, u_cpu.pipe_id_ex.ex_rd, u_cpu.pipe_if_id.id_instr[19:15]));

        assert_true("Load-Use Stall Controls: stall_pc, stall_if_id, flush_id_ex active",
                    (u_cpu.stall_pc === 1'b1 && u_cpu.stall_if_id === 1'b1 && u_cpu.flush_id_ex === 1'b1),
                    $sformatf("stall_pc=%b stall_if_id=%b flush_id_ex=%b",
                              u_cpu.stall_pc, u_cpu.stall_if_id, u_cpu.flush_id_ex));

        // Cycle 3: The Stall Cycle!
        // PC must be held at 0x08; IF/ID must hold Word 1 at PC=0x04; ID/EX must have bubble.
        @(posedge clk); #1;
        assert_true("Load-Use Hold Check: IF/ID instruction held at PC=0x04",
                    (u_cpu.pipe_if_id.id_pc === 32'h0000_0004 &&
                     u_cpu.pipe_if_id.id_instr === 32'h0190_8113),
                    $sformatf("id_pc=0x%08h, id_instr=0x%08h",
                              u_cpu.pipe_if_id.id_pc, u_cpu.pipe_if_id.id_instr));

        assert_true("Load-Use Bubble Check: ID/EX has injected bubble (ex_reg_write=0)",
                    (u_cpu.pipe_id_ex.ex_reg_write === 1'b0 &&
                     u_cpu.pipe_id_ex.ex_mem_read === 1'b0),
                    $sformatf("ex_reg_write=%b, ex_mem_read=%b",
                              u_cpu.pipe_id_ex.ex_reg_write, u_cpu.pipe_id_ex.ex_mem_read));

        assert_true("Load-Use Stall Recovery: Hazard deasserts after exactly 1 cycle",
                    (u_cpu.load_use_hazard === 1'b0 && u_cpu.stall_pc === 1'b0),
                    $sformatf("load_use_hazard=%b, stall_pc=%b",
                              u_cpu.load_use_hazard, u_cpu.stall_pc));

        // Advance pipeline until all Section 7 instructions complete
        repeat (35) @(posedge clk); #1;

        // Test 37: Verify Load-to-ALU Op A result (lw x1 -> addi x2, x1, 25 = 525)
        check_reg("Load-Use Op A Result: x2 = 500 + 25 = 525", 2, 32'd525);

        // Test 38: Verify Load-to-ALU Op B result (lw x3 -> sub x4, x0, x3 = -777)
        check_reg("Load-Use Op B Result: x4 = 0 - 777 = -777", 4, 32'hFFFF_FCF7);

        // Test 39: Verify Load-to-Store data forwarding with 1 stall (Mem[12] = 500)
        check_dmem("Load-Use Store Data Result: Mem[12] holds 500", 12, 32'd500);

        // Test 40: Verify Load-to-Branch stall and sequential continuation (x7 = 88)
        check_reg("Load-Use Branch Sequential Execution: x7 = 88", 7, 32'd88);

        // Test 41: Load to x0 does NOT trigger stall (x8 = 99)
        check_reg("Load to x0 No-Stall Execution: x8 = 99", 8, 32'd99);

        // Test 42: Immediate matching load rd does NOT trigger false rs2 stall (x9 = 20)
        check_reg("Immediate Matching rd No-False-Stall: x9 = 20", 9, 32'd20);

        // Tests 43-44: Stage 10D Independent Instructions Execution
        check_reg("Stage 10D Independent Inst A: x25 = 1", 25, 32'd1);
        check_reg("Stage 10D Independent Inst B: x26 = 2", 26, 32'd2);

        // =====================================================================
        // PART 3: Stage 10E Branch & Jump Control Hazards Suite
        // =====================================================================
        $display("------------------------------------------------------------------------------------------");
        $display("--- SECTION 8: Stage 10E Branch & Jump Control Hazards Directed Tests ---");
        $display("------------------------------------------------------------------------------------------");

        // Synchronous Reset & DUT Re-initialization for Stage 10E
        rst_n = 1'b0;
        #20;

        // Clear architectural registers
        for (int i = 0; i < 32; i++) begin
            u_cpu.reg_file.regs[i] = 32'd0;
        end

        // Clear and initialize Data Memory
        for (int i = 0; i < 64; i++) begin
            u_cpu.dmem.mem[i] = 32'd0;
        end
        u_cpu.dmem.mem[20] = 32'd42; // Byte address 80 (0x50)
        u_cpu.dmem.mem[21] = 32'd0;  // Byte address 84 (0x54)

        // Clear and initialize Instruction Memory
        for (int i = 0; i < 128; i++) begin
            u_cpu.imem.mem[i] = NOP_INSTR;
        end

        // ---------------------------------------------------------------------
        // Program Segment 1: BEQ Taken, Wrong-Path Flush, and Target Execution
        // ---------------------------------------------------------------------
        // Word 0 (0x00): addi x1, x0, 10
        u_cpu.imem.mem[0]  = 32'h00A0_0093;
        // Word 1 (0x04): addi x2, x0, 10
        u_cpu.imem.mem[1]  = 32'h00A0_0113;
        // Word 2 (0x08): beq  x1, x2, +16      (target = 0x18 = Word 6)
        u_cpu.imem.mem[2]  = 32'h0020_8863;
        // Word 3 (0x0C): addi x27, x0, 99     (WRONG-PATH 1: register write trap)
        u_cpu.imem.mem[3]  = 32'h0630_0D93;
        // Word 4 (0x10): sw   x1, 100(x0)     (WRONG-PATH 2: store write trap to Mem[25])
        u_cpu.imem.mem[4]  = 32'h0610_2223;
        // Word 5 (0x14): addi x28, x0, 88     (WRONG-PATH 3: register write trap)
        u_cpu.imem.mem[5]  = 32'h0580_0E13;
        // Word 6 (0x18): addi x3, x0, 30      (TARGET: x3 <= 30)
        u_cpu.imem.mem[6]  = 32'h01E0_0193;

        // ---------------------------------------------------------------------
        // Program Segment 2: BEQ Not-Taken (Sequential Execution, No Flush)
        // ---------------------------------------------------------------------
        // Word 7 (0x1C): addi x4, x0, 40
        u_cpu.imem.mem[7]  = 32'h0280_0213;
        // Word 8 (0x20): beq  x1, x4, +16      (10 != 40, NOT TAKEN)
        u_cpu.imem.mem[8]  = 32'h0040_8863;
        // Word 9 (0x24): addi x5, x0, 50      (Sequential: x5 <= 50)
        u_cpu.imem.mem[9]  = 32'h0320_0293;
        // Word 10(0x28): addi x6, x0, 60      (Sequential: x6 <= 60)
        u_cpu.imem.mem[10] = 32'h03C0_0313;

        // ---------------------------------------------------------------------
        // Program Segment 3: BNE Taken and Not-Taken
        // ---------------------------------------------------------------------
        // Word 11(0x2C): bne  x1, x4, +12      (10 != 40, TAKEN -> target 0x38 = Word 14)
        u_cpu.imem.mem[11] = 32'h0040_9663;
        // Word 12(0x30): addi x27, x0, 111    (WRONG-PATH trap)
        u_cpu.imem.mem[12] = 32'h06F0_0D93;
        // Word 13(0x34): addi x28, x0, 222    (WRONG-PATH trap)
        u_cpu.imem.mem[13] = 32'h0DE0_0E13;
        // Word 14(0x38): addi x7, x0, 70      (TARGET: x7 <= 70)
        u_cpu.imem.mem[14] = 32'h0460_0393;
        // Word 15(0x3C): bne  x1, x2, +12      (10 != 10 is false, NOT TAKEN)
        u_cpu.imem.mem[15] = 32'h0020_9663;
        // Word 16(0x40): addi x8, x0, 80      (Sequential: x8 <= 80)
        u_cpu.imem.mem[16] = 32'h0500_0413;

        // ---------------------------------------------------------------------
        // Program Segment 4: BLT / BGE Signed Comparisons
        // ---------------------------------------------------------------------
        // Word 17(0x44): addi x19, x0, -10    (0xFFFFFFF6)
        u_cpu.imem.mem[17] = 32'hFF60_0993;
        // Word 18(0x48): addi x20, x0, 20     (0x00000014)
        u_cpu.imem.mem[18] = 32'h0140_0A13;
        // Word 19(0x4C): blt  x19, x20, +12    (-10 < 20 signed true, TAKEN -> target 0x58 = Word 22)
        u_cpu.imem.mem[19] = 32'h0149_C663;
        // Word 20(0x50): addi x27, x0, 999    (WRONG-PATH trap)
        u_cpu.imem.mem[20] = 32'h3E70_0D93;
        // Word 21(0x54): addi x28, x0, 888    (WRONG-PATH trap)
        u_cpu.imem.mem[21] = 32'h3780_0E13;
        // Word 22(0x58): addi x9, x0, 90      (TARGET: x9 <= 90)
        u_cpu.imem.mem[22] = 32'h05A0_0493;
        // Word 23(0x5C): bge  x19, x20, +12    (-10 >= 20 signed false, NOT TAKEN)
        u_cpu.imem.mem[23] = 32'h0149_D663;
        // Word 24(0x60): addi x10, x0, 100    (Sequential: x10 <= 100)
        u_cpu.imem.mem[24] = 32'h0640_0513;
        // Word 25(0x64): bge  x20, x19, +12    (20 >= -10 signed true, TAKEN -> target 0x70 = Word 28)
        u_cpu.imem.mem[25] = 32'h013A_5663;
        // Word 26(0x68): addi x27, x0, 777    (WRONG-PATH trap)
        u_cpu.imem.mem[26] = 32'h3090_0D93;
        // Word 27(0x6C): addi x28, x0, 666    (WRONG-PATH trap)
        u_cpu.imem.mem[27] = 32'h29A0_0E13;
        // Word 28(0x70): addi x11, x0, 110    (TARGET: x11 <= 110)
        u_cpu.imem.mem[28] = 32'h06E0_0593;
        // Word 29(0x74): blt  x20, x19, +12    (20 < -10 signed false, NOT TAKEN)
        u_cpu.imem.mem[29] = 32'h013A_4663;
        // Word 30(0x78): addi x12, x0, 120    (Sequential: x12 <= 120)
        u_cpu.imem.mem[30] = 32'h0780_0613;

        // ---------------------------------------------------------------------
        // Program Segment 5: BLTU / BGEU Unsigned Comparisons
        // ---------------------------------------------------------------------
        // Word 31(0x7C): bltu x19, x20, +12    (0xFFFFFFF6 < 20 unsigned false, NOT TAKEN)
        u_cpu.imem.mem[31] = 32'h0149_E663;
        // Word 32(0x80): addi x13, x0, 130    (Sequential: x13 <= 130)
        u_cpu.imem.mem[32] = 32'h0820_0693;
        // Word 33(0x84): bgeu x19, x20, +12    (0xFFFFFFF6 >= 20 unsigned true, TAKEN -> target 0x90 = Word 36)
        u_cpu.imem.mem[33] = 32'h0149_F663;
        // Word 34(0x88): addi x27, x0, 555    (WRONG-PATH trap)
        u_cpu.imem.mem[34] = 32'h22B0_0D93;
        // Word 35(0x8C): addi x28, x0, 444    (WRONG-PATH trap)
        u_cpu.imem.mem[35] = 32'h1BC0_0E13;
        // Word 36(0x90): addi x14, x0, 140    (TARGET: x14 <= 140)
        u_cpu.imem.mem[36] = 32'h08C0_0713;

        // ---------------------------------------------------------------------
        // Program Segment 6: Forwarded Operands in Branch Comparison
        // ---------------------------------------------------------------------
        // Word 37(0x94): addi x21, x0, 77
        u_cpu.imem.mem[37] = 32'h04D0_0A93;
        // Word 38(0x98): beq  x21, x0, +12     (77 == 0 false, NOT TAKEN with EX/MEM forwarded x21)
        u_cpu.imem.mem[38] = 32'h000A_8663;
        // Word 39(0x9C): addi x22, x0, 222    (Sequential: x22 <= 222)
        u_cpu.imem.mem[39] = 32'h0DE0_0B13;
        // Word 40(0xA0): addi x23, x0, 77
        u_cpu.imem.mem[40] = 32'h04D0_0B93;
        // Word 41(0xA4): beq  x23, x21, +12    (77 == 77 true, TAKEN with dual forwarded operands -> target 0xB0 = Word 44)
        u_cpu.imem.mem[41] = 32'h015B_8663;
        // Word 42(0xA8): addi x27, x0, 333    (WRONG-PATH trap)
        u_cpu.imem.mem[42] = 32'h14D0_0D93;
        // Word 43(0xAC): addi x28, x0, 222    (WRONG-PATH trap)
        u_cpu.imem.mem[43] = 32'h0DE0_0E13;
        // Word 44(0xB0): addi x24, x0, 240    (TARGET: x24 <= 240)
        u_cpu.imem.mem[44] = 32'h0F00_0C13;

        // ---------------------------------------------------------------------
        // Program Segment 7: JAL Redirection, Link Address (PC+4) & Link Forwarding
        // ---------------------------------------------------------------------
        // Word 45(0xB4): jal  x15, +16         (target = 0xB4 + 16 = 0xC4 = Word 49. Link x15 <= 0xB8)
        u_cpu.imem.mem[45] = 32'h0100_07EF;
        // Word 46(0xB8): addi x27, x0, 111    (WRONG-PATH trap)
        u_cpu.imem.mem[46] = 32'h06F0_0D93;
        // Word 47(0xBC): addi x28, x0, 111    (WRONG-PATH trap)
        u_cpu.imem.mem[47] = 32'h06F0_0E13;
        // Word 48(0xC0): addi x29, x0, 111    (WRONG-PATH trap)
        u_cpu.imem.mem[48] = 32'h06F0_0E93;
        // Word 49(0xC4): addi x25, x15, 10    (TARGET: consumes forwarded link x15=0xB8 -> x25 <= 0xB8+10 = 0xC2=194)
        u_cpu.imem.mem[49] = 32'h00A7_8C93;

        // ---------------------------------------------------------------------
        // Program Segment 8: JALR Redirection, Bit-0 Clear, Link Address & Forwarding
        // ---------------------------------------------------------------------
        // Word 50(0xC8): addi x26, x0, 220    (0xDC = Word 55)
        u_cpu.imem.mem[50] = 32'h0DC0_0D13;
        // Word 51(0xCC): addi x26, x26, 1     (x26 <= 0xDD, odd target address with bit 0 = 1)
        u_cpu.imem.mem[51] = 32'h001D_0D13;
        // Word 52(0xD0): jalr x16, 0(x26)     (target = 0xDD & ~1 = 0xDC = Word 55. Link x16 <= 0xD4)
        u_cpu.imem.mem[52] = 32'h000D_0867;
        // Word 53(0xD4): addi x27, x0, 99     (WRONG-PATH trap)
        u_cpu.imem.mem[53] = 32'h0630_0D93;
        // Word 54(0xD8): addi x28, x0, 99     (WRONG-PATH trap)
        u_cpu.imem.mem[54] = 32'h0630_0E13;
        // Word 55(0xDC): addi x30, x16, 5     (TARGET: consumes forwarded link x16=0xD4 -> x30 <= 0xD4+5 = 0xD9=217)
        u_cpu.imem.mem[55] = 32'h0058_0F13;

        // ---------------------------------------------------------------------
        // Program Segment 9: JAL to x0 (Suppress Link Writeback, No x0 Corruption)
        // ---------------------------------------------------------------------
        // Word 56(0xE0): jal  x0, +12          (target = 0xE0 + 12 = 0xEC = Word 59)
        u_cpu.imem.mem[56] = 32'h00C0_006F;
        // Word 57(0xE4): addi x27, x0, 88     (WRONG-PATH trap)
        u_cpu.imem.mem[57] = 32'h0580_0D93;
        // Word 58(0xE8): addi x28, x0, 88     (WRONG-PATH trap)
        u_cpu.imem.mem[58] = 32'h0580_0E13;
        // Word 59(0xEC): addi x31, x0, 310    (TARGET: x31 <= 310)
        u_cpu.imem.mem[59] = 32'h1360_0F93;

        // ---------------------------------------------------------------------
        // Program Segment 10: Load-Use Hazard Immediately Preceding Branch
        // ---------------------------------------------------------------------
        // Word 60(0xF0): lw   x17, 80(x0)     (Mem[20] holds 42 -> x17 <= 42)
        u_cpu.imem.mem[60] = 32'h0500_2883;
        // Word 61(0xF4): beq  x17, x0, +12    (42 == 0 false, NOT TAKEN after 1-cycle stall)
        u_cpu.imem.mem[61] = 32'h0008_8663;
        // Word 62(0xF8): addi x18, x0, 202    (Sequential: x18 <= 202)
        u_cpu.imem.mem[62] = 32'h0CA0_0913;
        // Word 63(0xFC): lw   x1, 84(x0)      (Mem[21] holds 0 -> x1 <= 0)
        u_cpu.imem.mem[63] = 32'h0540_2083;
        // Word 64(0x100): beq x1, x0, +12     (0 == 0 true, TAKEN after 1-cycle stall -> target 0x10C = Word 67)
        u_cpu.imem.mem[64] = 32'h0000_8663;
        // Word 65(0x104): addi x27, x0, 77    (WRONG-PATH trap)
        u_cpu.imem.mem[65] = 32'h04D0_0D93;
        // Word 66(0x108): addi x28, x0, 77    (WRONG-PATH trap)
        u_cpu.imem.mem[66] = 32'h04D0_0E13;
        // Word 67(0x10C): addi x2, x0, 404    (TARGET: x2 <= 404)
        u_cpu.imem.mem[67] = 32'h1940_0113;

        // ---------------------------------------------------------------------
        // Program Segment 11: Back-to-Back Redirects
        // ---------------------------------------------------------------------
        // Word 68(0x110): jal x0, +8          (target = 0x118 = Word 70)
        u_cpu.imem.mem[68] = 32'h0080_006F;
        // Word 69(0x114): addi x27, x0, 66    (WRONG-PATH trap)
        u_cpu.imem.mem[69] = 32'h0420_0D93;
        // Word 70(0x118): jal x0, +8          (target = 0x120 = Word 72)
        u_cpu.imem.mem[70] = 32'h0080_006F;
        // Word 71(0x11C): addi x27, x0, 66    (WRONG-PATH trap)
        u_cpu.imem.mem[71] = 32'h0420_0D93;
        // Word 72(0x120): sw  x17, 120(x0)    (TARGET: writes Mem[30] <= 42)
        u_cpu.imem.mem[72] = 32'h0710_2C23;

        // ---------------------------------------------------------------------
        // Program Segment 12: Load-Use Hazard Immediately Preceding JALR (Item G)
        // ---------------------------------------------------------------------
        u_cpu.dmem.mem[22] = 32'h0000_0138;   // Target address 0x138 (Word 78)
        // Word 73(0x124): lw   x1, 88(x0)     (Mem[22] holds 0x138 -> x1 <= 0x138)
        u_cpu.imem.mem[73] = 32'h0580_2083;
        // Word 74(0x128): jalr x4, 0(x1)      (Consumes x1 from load! Target = 0x138 = Word 78. Link x4 <= 0x12C)
        u_cpu.imem.mem[74] = 32'h0000_8267;
        // Word 75(0x12C): addi x27, x0, 55    (WRONG-PATH trap)
        u_cpu.imem.mem[75] = 32'h0370_0D93;
        // Word 76(0x130): addi x28, x0, 55    (WRONG-PATH trap)
        u_cpu.imem.mem[76] = 32'h0370_0E13;
        // Word 77(0x134): addi x29, x0, 55    (WRONG-PATH trap)
        u_cpu.imem.mem[77] = 32'h0370_0E93;
        // Word 78(0x138): addi x17, x4, 2     (TARGET: consumes forwarded link x4=0x12C -> x17 <= 0x12E = 302)
        u_cpu.imem.mem[78] = 32'h0022_0893;

        // ---------------------------------------------------------------------
        // Program Segment 13: Backward Branch (Item J)
        // ---------------------------------------------------------------------
        // Word 79(0x13C): jal  x0, +16        (jumps forward to Word 83 = 0x14C)
        u_cpu.imem.mem[79] = 32'h0100_006F;
        // Word 80(0x140): addi x19, x0, 333   (TARGET OF BACKWARD BRANCH: x19 <= 333)
        u_cpu.imem.mem[80] = 32'h14D0_0993;
        // Word 81(0x144): jal  x0, +16        (jumps forward to Word 85 = 0x154)
        u_cpu.imem.mem[81] = 32'h0100_006F;
        // Word 82(0x148): addi x27, x0, 44    (WRONG-PATH trap)
        u_cpu.imem.mem[82] = 32'h02C0_0D93;
        // Word 83(0x14C): beq  x0, x0, -12    (BACKWARD BRANCH: 0x14C - 12 = 0x140 = Word 80!)
        u_cpu.imem.mem[83] = 32'hFE00_0AE3;
        // Word 84(0x150): addi x28, x0, 44    (WRONG-PATH trap)
        u_cpu.imem.mem[84] = 32'h02C0_0E13;
        // Word 85(0x154): addi x20, x0, 444   (CONTINUATION: x20 <= 444)
        u_cpu.imem.mem[85] = 32'h1BC0_0A13;

        // ---------------------------------------------------------------------
        // Program Segment 14: Redirect Priority over Younger Hazard Request (Item I)
        // ---------------------------------------------------------------------
        // Word 86(0x158): lw   x26, 80(x0)    (loads from Mem[20]=42 into x26)
        u_cpu.imem.mem[86] = 32'h0500_2D03;
        // Word 87(0x15C): jal  x0, +16        (unconditional jump to Word 91 = 0x16C)
        u_cpu.imem.mem[87] = 32'h0100_006F;
        // Word 88(0x160): addi x23, x26, 1    (WRONG-PATH consumer of x26! Must be squashed with ZERO stalls!)
        u_cpu.imem.mem[88] = 32'h001D_0B93;
        // Word 89(0x164): addi x27, x0, 33    (WRONG-PATH trap)
        u_cpu.imem.mem[89] = 32'h0210_0D93;
        // Word 90(0x168): addi x28, x0, 33    (WRONG-PATH trap)
        u_cpu.imem.mem[90] = 32'h0210_0E13;
        // Word 91(0x16C): addi x21, x0, 555   (TARGET: x21 <= 555)
        u_cpu.imem.mem[91] = 32'h22B0_0A93;

        // ---------------------------------------------------------------------
        // Program Segment 15: Final Unsigned Branch Coverage (BLTU Taken & BGEU Not-Taken)
        // ---------------------------------------------------------------------
        // Word 92(0x170): addi x1, x0, 20      (Setup rs1 = 20)
        u_cpu.imem.mem[92]  = 32'h0140_0093;
        // Word 93(0x174): addi x26, x0, -10    (Setup rs2 = 0xFFFFFFF6)
        u_cpu.imem.mem[93]  = 32'hFF60_0D13;
        // Word 94(0x178): bltu x1, x26, +16    (20 < 0xFFFFFFF6 unsigned true, TAKEN -> target 0x188 = Word 98)
        u_cpu.imem.mem[94]  = 32'h01AE_6863;
        // Word 95(0x17C): addi x27, x0, 99     (WRONG-PATH trap 1: register write)
        u_cpu.imem.mem[95]  = 32'h0630_0D93;
        // Word 96(0x180): sw   x1, 100(x0)     (WRONG-PATH trap 2: store write to Mem[25])
        u_cpu.imem.mem[96]  = 32'h0610_2223;
        // Word 97(0x184): addi x28, x0, 99     (WRONG-PATH trap 3: register write)
        u_cpu.imem.mem[97]  = 32'h0630_0E13;
        // Word 98(0x188): sw   x1, 140(x0)     (TARGET: writes Mem[35] <= 20; x1 remains 20, x26 remains 0xFFFFFFF6)
        u_cpu.imem.mem[98]  = 32'h0810_2623;
        // Word 99(0x18C): bgeu x1, x26, +16    (20 >= 0xFFFFFFF6 unsigned false, NOT TAKEN -> sequential)
        u_cpu.imem.mem[99]  = 32'h01AF_7863;
        // Word 100(0x190): addi x1, x0, 222    (Sequential: x1 <= 222)
        u_cpu.imem.mem[100] = 32'h0DE0_0093;
        // Word 101(0x194): jal  x0, +12        (Jumps over erroneous taken target to Word 104 = 0x1A0)
        u_cpu.imem.mem[101] = 32'h00C0_006F;
        // Word 102(0x198): addi x27, x0, 99    (WRONG-PATH trap)
        u_cpu.imem.mem[102] = 32'h0630_0D93;
        // Word 103(0x19C): addi x28, x0, 88    (ERRONEOUS TAKEN TARGET trap: would corrupt x28 if bgeu taken)
        u_cpu.imem.mem[103] = 32'h0580_0E13;
        // Word 104(0x1A0): nop                 (addi x0, x0, 0)
        u_cpu.imem.mem[104] = 32'h0000_0013;

        // Release reset synchronously
        @(negedge clk);
        rst_n = 1'b1;

        // Cycle 1: Word 0 in ID (PC=0x00), Word 1 in IF (PC=0x04)
        @(posedge clk); #1;
        // Cycle 2: Word 0 in EX, Word 1 in ID, Word 2 (beq) in IF
        @(posedge clk); #1;
        // Cycle 3: Word 0 in MEM, Word 1 in EX, Word 2 (beq) in ID
        @(posedge clk); #1;

        // Cycle 4: Word 2 (beq x1, x2) enters EX!
        // Operands x1=10 (from MEM), x2=10 (from EX) forwarded! Branch taken!
        @(posedge clk); #1;
        assert_true("Taken Branch: ex_redirect active and target is 0x00000018",
                    (u_cpu.ex_redirect === 1'b1 && u_cpu.ex_redirect_target === 32'h0000_0018),
                    $sformatf("ex_redirect=%b, target=0x%08h", u_cpu.ex_redirect, u_cpu.ex_redirect_target));

        assert_true("Taken Branch Flush Controls: flush_if_id and flush_id_ex asserted",
                    (u_cpu.flush_if_id === 1'b1 && u_cpu.flush_id_ex === 1'b1),
                    $sformatf("flush_if_id=%b, flush_id_ex=%b", u_cpu.flush_if_id, u_cpu.flush_id_ex));

        // Cycle 5: Clock edge updates PC to target, clears ID/EX and IF/ID
        @(posedge clk); #1;
        assert_true("Taken Branch Redirection: IF PC updated to 0x00000018",
                    (u_cpu.if_pc === 32'h0000_0018),
                    $sformatf("if_pc=0x%08h", u_cpu.if_pc));

        assert_true("Taken Branch Flush Effect: ID/EX has injected bubble",
                    (u_cpu.pipe_id_ex.ex_reg_write === 1'b0 && u_cpu.pipe_id_ex.ex_mem_write === 1'b0),
                    $sformatf("ex_reg_write=%b, ex_mem_write=%b",
                              u_cpu.pipe_id_ex.ex_reg_write, u_cpu.pipe_id_ex.ex_mem_write));

        assert_true("Taken Branch Flush Effect: IF/ID has injected NOP",
                    (u_cpu.pipe_if_id.id_instr === NOP_INSTR),
                    $sformatf("id_instr=0x%08h", u_cpu.pipe_if_id.id_instr));

        // Advance through all Section 8 instructions (175 clock cycles)
        repeat (175) @(posedge clk); #1;

        // ---------------------------------------------------------------------
        // Verifying Architectural Results for Stage 10E
        // ---------------------------------------------------------------------
        // Segment 1 Results:
        check_reg("Taken BEQ Target Commit: x3 = 30", 3, 32'd30);
        check_reg("Wrong-Path Reg Trap Suppressed: x27 = 0", 27, 32'd0);
        check_reg("Wrong-Path Reg Trap Suppressed: x28 = 0", 28, 32'd0);
        check_reg("Wrong-Path Reg Trap Suppressed: x29 = 0", 29, 32'd0);
        check_dmem("Wrong-Path Store Write Suppressed: Mem[25] = 0", 25, 32'd0);

        // Segment 2 Results (Not-taken BEQ):
        check_reg("Not-Taken BEQ Sequential Commit 1: x5 = 50", 5, 32'd50);
        check_reg("Not-Taken BEQ Sequential Commit 2: x6 = 60", 6, 32'd60);

        // Segment 3 Results (BNE taken and not-taken):
        check_reg("Taken BNE Target Commit: x7 = 70", 7, 32'd70);
        check_reg("Not-Taken BNE Sequential Commit: x8 = 80", 8, 32'd80);

        // Segment 4 Results (BLT / BGE signed comparisons):
        check_reg("BLT Signed (-10 < 20) Taken Commit: x9 = 90", 9, 32'd90);
        check_reg("BGE Signed (-10 >= 20) Not-Taken Commit: x10 = 100", 10, 32'd100);
        check_reg("BGE Signed (20 >= -10) Taken Commit: x11 = 110", 11, 32'd110);
        check_reg("BLT Signed (20 < -10) Not-Taken Commit: x12 = 120", 12, 32'd120);

        // Segment 5 Results (BLTU / BGEU unsigned comparisons):
        check_reg("BLTU Unsigned (0xFFFFFFF6 < 20) Not-Taken: x13 = 130", 13, 32'd130);
        check_reg("BGEU Unsigned (0xFFFFFFF6 >= 20) Taken: x14 = 140", 14, 32'd140);

        // Segment 6 Results (Forwarded Operands in Branch Decisions):
        check_reg("Branch Forwarded Op Not-Taken Commit: x22 = 222", 22, 32'd222);
        check_reg("Branch Dual Forwarded Ops Taken Commit: x24 = 240", 24, 32'd240);

        // Segment 7 Results (JAL Target & Link PC+4 & Forwarding):
        check_reg("JAL Link Address PC+4 Commit: x15 = 0x000000B8 (184)", 15, 32'h0000_00B8);
        check_reg("JAL Forwarded Link Dependent Commit: x25 = 194", 25, 32'd194);

        // Segment 8 Results (JALR Target Bit-0 Clear & Link & Forwarding):
        check_reg("JALR Link Address PC+4 Commit: x16 = 0x000000D4 (212)", 16, 32'h0000_00D4);
        check_reg("JALR Forwarded Link Dependent Commit: x30 = 217", 30, 32'd217);

        // Segment 9 Results (JAL to x0):
        check_reg("JAL to x0 Immunity: x0 strictly remains 0", 0, 32'd0);
        check_reg("JAL to x0 Target Commit: x31 = 310", 31, 32'd310);

        // Segment 10 Results (Load-Use Dependency Immediately Preceding Branch):
        check_reg("Load-Use Preceding Not-Taken Branch Commit: x18 = 202", 18, 32'd202);
        check_reg("Load-Use Preceding Taken Branch Commit: x2 = 404", 2, 32'd404);

        // Segment 11 Results (Back-to-Back Redirects):
        check_dmem("Back-to-Back Redirects Final Target Commit: Mem[30] = 42", 30, 32'd42);

        // Segment 12 Results (Load-Use Dependency Immediately Preceding JALR):
        check_reg("Load-Use Preceding JALR Link Address: x4 = 0x0000012C", 4, 32'h0000_012C);
        check_reg("Load-Use Preceding JALR Forwarded Target: x17 = 302", 17, 32'd302);

        // Segment 13 Results (Backward Branch):
        check_reg("Backward Branch Target Commit: x19 = 333", 19, 32'd333);
        check_reg("Backward Branch Continuation Commit: x20 = 444", 20, 32'd444);

        // Segment 14 Results (Redirect Priority over Younger Hazard Request):
        check_reg("Redirect Priority Target Commit: x21 = 555", 21, 32'd555);
        check_reg("Redirect Priority Younger Squashed: x23 = 77 (not overwritten to 43)", 23, 32'd77);

        // Segment 15 Results (Final Unsigned Branch Coverage: BLTU Taken & BGEU Not-Taken):
        assert_true("BLTU Unsigned (20 < 0xFFFFFFF6) Taken: Target Mem[35]=20, Traps Suppressed",
                    (u_cpu.dmem.mem[35] === 32'd20 && u_cpu.reg_file.regs[27] === 32'd0 && u_cpu.dmem.mem[25] === 32'd0),
                    $sformatf("Mem[35]=0x%08h, x27=0x%08h, Mem[25]=0x%08h",
                              u_cpu.dmem.mem[35], u_cpu.reg_file.regs[27], u_cpu.dmem.mem[25]));
        check_reg("BGEU Unsigned (20 >= 0xFFFFFFF6) Not-Taken: Sequential Commit x1 = 222", 1, 32'd222);

        // ---------------------------------------------------------------------
        // Final Summary & Exit
        // ---------------------------------------------------------------------
        $display("==========================================================================================");
        $display("   RV32I 5-Stage Pipelined CPU (Stage 10E) Summary: Total=%0d | Passed=%0d | Failed=%0d",
                 test_count, pass_count, fail_count);
        $display("==========================================================================================");

        if (fail_count == 0) begin
            $display(">>> ALL %0d/%0d PIPELINED CPU STAGE 10E TESTS PASSED SUCCESSFULLY! <<<",
                     test_count, test_count);
            $finish(0);
        end else begin
            $display(">>> PIPELINED CPU TESTBENCH FAILED (%0d ERRORS) <<<", fail_count);
            $fatal(1, "Terminating due to verification failure.");
        end
    end

endmodule
