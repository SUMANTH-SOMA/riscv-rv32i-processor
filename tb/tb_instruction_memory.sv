`timescale 1ns / 1ps

// =============================================================================
// Module: tb_instruction_memory
// Project: RV32I RISC-V Processor (Stage 6)
// Description:
//   Self-checking verification testbench for simulation instruction memory.
//   Verifies default NOP initialization, sequential word addressing (0, 4, 8, 12),
//   hierarchical instruction pre-loading and retrieval, unaligned address
//   truncation behavior, and out-of-range boundary safety (returning NOP).
// =============================================================================

module tb_instruction_memory;

    localparam int WORDS = 256;
    localparam logic [31:0] NOP_INSTR = 32'h0000_0013;

    // DUT Signals
    logic [31:0] addr;
    logic [31:0] instr;

    // Test Tracking
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;

    // Instantiate DUT
    instruction_memory #(
        .WORDS(WORDS)
    ) dut (
        .addr(addr),
        .instr(instr)
    );

    // Self-checking verification task
    task check_fetch(
        input string       test_name,
        input logic [31:0] in_addr,
        input logic [31:0] exp_instr
    );
        begin
            test_count++;
            addr = in_addr;

            #1; // Propagation delay for combinational read

            if (instr === exp_instr) begin
                pass_count++;
                $display("[PASS] Test %02d: %-38s | Addr=0x%08h (Word %0d) -> Instr=0x%08h",
                         test_count, test_name, in_addr, in_addr >> 2, instr);
            end else begin
                fail_count++;
                $display("[FAIL] Test %02d: %s | Addr=0x%08h", test_count, test_name, in_addr);
                $display("       Expected: 0x%08h", exp_instr);
                $display("       Actual:   0x%08h", instr);
            end
        end
    endtask

    // Main Test Sequence
    initial begin
        // Configure waveform dump for GTKWave inspection
        $dumpfile("sim/instruction_memory.vcd");
        $dumpvars(0, tb_instruction_memory);

        $display("==========================================================================================");
        $display("   RV32I Instruction Memory Verification Testbench Started");
        $display("==========================================================================================");

        // -------------------------------------------------------------
        // Group 1: Default Initialization Verification (All words NOP)
        // -------------------------------------------------------------
        check_fetch("Default initialization at address 0",
                    32'd0, NOP_INSTR);

        check_fetch("Default initialization at address 4",
                    32'd4, NOP_INSTR);

        check_fetch("Default initialization at address 8",
                    32'd8, NOP_INSTR);

        check_fetch("Default initialization at address 12",
                    32'd12, NOP_INSTR);

        check_fetch("Default initialization at last word (1020)",
                    32'd1020, NOP_INSTR);

        // -------------------------------------------------------------
        // Group 2: Hierarchical Instruction Pre-loading
        // -------------------------------------------------------------
        $display("--- Loading test program instructions hierarchically into memory ---");
        dut.mem[0]   = 32'h02A0_0093; // addi x1, x0, 42
        dut.mem[1]   = 32'h0050_8113; // addi x2, x1, 5
        dut.mem[2]   = 32'h0020_81B3; // add  x3, x1, x2
        dut.mem[3]   = 32'h4020_8233; // sub  x4, x1, x2
        dut.mem[255] = 32'h0000_8067; // jalr x0, 0(x1) (last word index 255)

        // -------------------------------------------------------------
        // Group 3: Sequential Aligned Address Fetch Verification
        // -------------------------------------------------------------
        check_fetch("Fetch loaded Word 0 (addi x1, x0, 42)",
                    32'd0, 32'h02A0_0093);

        check_fetch("Fetch loaded Word 1 (addi x2, x1, 5)",
                    32'd4, 32'h0050_8113);

        check_fetch("Fetch loaded Word 2 (add  x3, x1, x2)",
                    32'd8, 32'h0020_81B3);

        check_fetch("Fetch loaded Word 3 (sub  x4, x1, x2)",
                    32'd12, 32'h4020_8233);

        check_fetch("Fetch loaded Word 255 (jalr x0, 0(x1))",
                    32'd1020, 32'h0000_8067);

        // -------------------------------------------------------------
        // Group 4: Unaligned Address Policy Verification (Truncate to Word)
        // -------------------------------------------------------------
        check_fetch("Unaligned byte offset +1 within Word 0",
                    32'd1, 32'h02A0_0093);

        check_fetch("Unaligned byte offset +2 within Word 0",
                    32'd2, 32'h02A0_0093);

        check_fetch("Unaligned byte offset +3 within Word 0",
                    32'd3, 32'h02A0_0093);

        check_fetch("Unaligned byte offset +1 within Word 1",
                    32'd5, 32'h0050_8113);

        check_fetch("Unaligned byte offset +3 within Word 1",
                    32'd7, 32'h0050_8113);

        // -------------------------------------------------------------
        // Group 5: Out-of-Range Boundary Safety Verification
        // -------------------------------------------------------------
        check_fetch("Out-of-range immediate boundary (Word 256)",
                    32'd1024, NOP_INSTR);

        check_fetch("Out-of-range Word 257 (Addr 1028)",
                    32'd1028, NOP_INSTR);

        check_fetch("Out-of-range high address (Addr 0x00010000)",
                    32'h0001_0000, NOP_INSTR);

        check_fetch("Out-of-range top memory space (Addr 0xFFFFFFFC)",
                    32'hFFFF_FFFC, NOP_INSTR);

        // -------------------------------------------------------------
        // Summary & Exit Status
        // -------------------------------------------------------------
        $display("==========================================================================================");
        $display("   Instruction Memory Summary: Total=%0d | Passed=%0d | Failed=%0d",
                 test_count, pass_count, fail_count);
        $display("==========================================================================================");

        if (fail_count == 0) begin
            $display(">>> ALL INSTRUCTION MEMORY TESTS PASSED SUCCESSFULLY! <<<");
            $finish(0);
        end else begin
            $display(">>> INSTRUCTION MEMORY TESTBENCH FAILED (%0d ERRORS) <<<", fail_count);
            $fatal(1, "Terminating due to verification failure.");
        end
    end

endmodule
