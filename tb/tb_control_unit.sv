`timescale 1ns / 1ps

// =============================================================================
// Module: tb_control_unit
// Project: RV32I RISC-V Processor (Stage 5)
// Description:
//   Self-checking verification testbench for RV32I Control Unit.
//   Exhaustively tests all 9 supported instruction classes and 3 unsupported
//   opcodes, verifying every single control output line against expected values.
//   Dumps VCD waveforms to sim/control_unit.vcd.
// =============================================================================

module tb_control_unit;

    // DUT Signals
    logic [6:0] opcode;
    logic       reg_write;
    logic       mem_read;
    logic       mem_write;
    logic       mem_to_reg;
    logic       alu_src;
    logic       branch;
    logic       jump;
    logic [2:0] imm_src;
    logic [1:0] alu_op;

    // Test Tracking
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;

    // Instantiate DUT
    control_unit dut (
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

    // Self-checking task verifying all 9 control output signals
    task check_controls(
        input string       test_name,
        input logic [6:0]  in_opcode,
        input logic        exp_reg_write,
        input logic        exp_mem_read,
        input logic        exp_mem_write,
        input logic        exp_mem_to_reg,
        input logic        exp_alu_src,
        input logic        exp_branch,
        input logic        exp_jump,
        input logic [2:0]  exp_imm_src,
        input logic [1:0]  exp_alu_op
    );
        begin
            test_count++;
            opcode = in_opcode;

            #1; // Propagation delay for combinational settling

            if ((reg_write  === exp_reg_write)  &&
                (mem_read   === exp_mem_read)   &&
                (mem_write  === exp_mem_write)  &&
                (mem_to_reg === exp_mem_to_reg) &&
                (alu_src    === exp_alu_src)    &&
                (branch     === exp_branch)     &&
                (jump       === exp_jump)       &&
                (imm_src    === exp_imm_src)    &&
                (alu_op     === exp_alu_op)) begin
                pass_count++;
                $display("[PASS] Test %02d: %-25s | Opcode=%b -> RW=%b MR=%b MW=%b M2R=%b ASrc=%b Br=%b Jmp=%b ImmSrc=%b AluOp=%b",
                         test_count, test_name, in_opcode, reg_write, mem_read, mem_write,
                         mem_to_reg, alu_src, branch, jump, imm_src, alu_op);
            end else begin
                fail_count++;
                $display("[FAIL] Test %02d: %s | Opcode=%b", test_count, test_name, in_opcode);
                $display("       Expected: RW=%b MR=%b MW=%b M2R=%b ASrc=%b Br=%b Jmp=%b ImmSrc=%b AluOp=%b",
                         exp_reg_write, exp_mem_read, exp_mem_write, exp_mem_to_reg,
                         exp_alu_src, exp_branch, exp_jump, exp_imm_src, exp_alu_op);
                $display("       Actual:   RW=%b MR=%b MW=%b M2R=%b ASrc=%b Br=%b Jmp=%b ImmSrc=%b AluOp=%b",
                         reg_write, mem_read, mem_write, mem_to_reg,
                         alu_src, branch, jump, imm_src, alu_op);
            end
        end
    endtask

    // Main Test Stimulus
    initial begin
        // Configure waveform dump for GTKWave inspection
        $dumpfile("sim/control_unit.vcd");
        $dumpvars(0, tb_control_unit);

        $display("==========================================================================================");
        $display("   RV32I Control Unit Verification Testbench Started");
        $display("==========================================================================================");

        // -------------------------------------------------------------
        // Supported Instruction Classes
        // -------------------------------------------------------------
        // Test 1: R-type (0110011)
        check_controls("R-type Arithmetic",
                       7'b0110011,
                       1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 3'b000, 2'b10);

        // Test 2: I-type Arithmetic (0010011)
        check_controls("I-type Arithmetic",
                       7'b0010011,
                       1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 3'b000, 2'b11);

        // Test 3: Load (0000011)
        check_controls("Load Instruction",
                       7'b0000011,
                       1'b1, 1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 3'b000, 2'b00);

        // Test 4: Store (0100011)
        check_controls("Store Instruction",
                       7'b0100011,
                       1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 3'b001, 2'b00);

        // Test 5: Branch (1100011)
        check_controls("Branch Instruction",
                       7'b1100011,
                       1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 3'b010, 2'b01);

        // Test 6: LUI (0110111)
        check_controls("LUI Instruction",
                       7'b0110111,
                       1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 3'b011, 2'b00);

        // Test 7: AUIPC (0010111)
        check_controls("AUIPC Instruction",
                       7'b0010111,
                       1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 3'b011, 2'b00);

        // Test 8: JAL (1101111)
        check_controls("JAL Instruction",
                       7'b1101111,
                       1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 3'b100, 2'b00);

        // Test 9: JALR (1100111)
        check_controls("JALR Instruction",
                       7'b1100111,
                       1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 3'b000, 2'b00);

        // -------------------------------------------------------------
        // Unsupported / Illegal Opcodes (safe defaults test)
        // -------------------------------------------------------------
        // Test 10: All zeros (0000000)
        check_controls("Unsupported (All Zeros)",
                       7'b0000000,
                       1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 3'b000, 2'b00);

        // Test 11: All ones (1111111)
        check_controls("Unsupported (All Ones)",
                       7'b1111111,
                       1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 3'b000, 2'b00);

        // Test 12: Arbitrary unmapped opcode (1010101)
        check_controls("Unsupported (Arbitrary 1010101)",
                       7'b1010101,
                       1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 3'b000, 2'b00);

        // -------------------------------------------------------------
        // Summary & Exit Status
        // -------------------------------------------------------------
        $display("==========================================================================================");
        $display("   Control Unit Summary: Total=%0d | Passed=%0d | Failed=%0d",
                 test_count, pass_count, fail_count);
        $display("==========================================================================================");

        if (fail_count == 0) begin
            $display(">>> ALL CONTROL UNIT TESTS PASSED SUCCESSFULLY! <<<");
            $finish(0);
        end else begin
            $display(">>> CONTROL UNIT TESTBENCH FAILED (%0d ERRORS) <<<", fail_count);
            $fatal(1, "Terminating due to verification failure.");
        end
    end

endmodule
