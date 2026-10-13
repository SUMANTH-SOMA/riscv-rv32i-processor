`timescale 1ns / 1ps

// =============================================================================
// Module: tb_alu
// Project: RV32I RISC-V Processor (Stage 2)
// Description:
//   Self-checking testbench for 32-bit ALU.
//   Verifies ADD, SUB, AND, OR, XOR operations across nominal, boundary,
//   and zero-result conditions. Dumps VCD waveforms to sim/alu.vcd.
// =============================================================================

module tb_alu;

    // DUT Signals
    logic [31:0] a;
    logic [31:0] b;
    logic [3:0]  alu_op;
    logic [31:0] alu_result;
    logic        zero;

    // Operation Selector Encodings (matching rtl/alu.sv)
    localparam logic [3:0] ALU_ADD = 4'b0000;
    localparam logic [3:0] ALU_SUB = 4'b1000;
    localparam logic [3:0] ALU_XOR = 4'b0100;
    localparam logic [3:0] ALU_OR  = 4'b0110;
    localparam logic [3:0] ALU_AND = 4'b0111;

    // Test Tracking Variables
    int test_count   = 0;
    int pass_count   = 0;
    int fail_count   = 0;

    // Instantiate Device Under Test (DUT)
    alu dut (
        .a(a),
        .b(b),
        .alu_op(alu_op),
        .alu_result(alu_result),
        .zero(zero)
    );

    // Self-checking verification task
    task check_alu(
        input string       test_name,
        input logic [3:0]  op,
        input logic [31:0] in_a,
        input logic [31:0] in_b,
        input logic [31:0] exp_result,
        input logic        exp_zero
    );
        begin
            test_count++;
            a      = in_a;
            b      = in_b;
            alu_op = op;

            #1; // Propagation delay for combinational logic settling

            if ((alu_result === exp_result) && (zero === exp_zero)) begin
                pass_count++;
                $display("[PASS] Test %02d: %s | A=0x%08h B=0x%08h Op=%b -> Result=0x%08h Zero=%b",
                         test_count, test_name, in_a, in_b, op, alu_result, zero);
            end else begin
                fail_count++;
                $display("[FAIL] Test %02d: %s | A=0x%08h B=0x%08h Op=%b",
                         test_count, test_name, in_a, in_b, op);
                $display("       Expected: Result=0x%08h, Zero=%b", exp_result, exp_zero);
                $display("       Actual:   Result=0x%08h, Zero=%b", alu_result, zero);
            end
        end
    endtask

    // Main Test Sequence
    initial begin
        // Configure waveform dump for GTKWave inspection
        $dumpfile("sim/alu.vcd");
        $dumpvars(0, tb_alu);

        $display("==================================================================");
        $display("   RV32I 32-bit ALU Verification Testbench Started");
        $display("==================================================================");

        // -------------------------------------------------------------
        // Group 1: ADD Operations
        // -------------------------------------------------------------
        check_alu("ADD: Positive integers",
                  ALU_ADD, 32'd15, 32'd27, 32'd42, 1'b0);

        check_alu("ADD: Positive + Negative (non-zero)",
                  ALU_ADD, 32'd50, -32'd20, 32'd30, 1'b0);

        check_alu("ADD: Cancellation to Zero",
                  ALU_ADD, 32'd100, -32'd100, 32'd0, 1'b1);

        check_alu("ADD: Signed Overflow Boundary (MAX_INT + 1)",
                  ALU_ADD, 32'h7FFF_FFFF, 32'h0000_0001, 32'h8000_0000, 1'b0);

        check_alu("ADD: Unsigned Wrap-Around Boundary (ALL_ONES + 1)",
                  ALU_ADD, 32'hFFFF_FFFF, 32'h0000_0001, 32'h0000_0000, 1'b1);

        // -------------------------------------------------------------
        // Group 2: SUB Operations
        // -------------------------------------------------------------
        check_alu("SUB: Positive integers (A > B)",
                  ALU_SUB, 32'd100, 32'd35, 32'd65, 1'b0);

        check_alu("SUB: Positive integers yielding negative (A < B)",
                  ALU_SUB, 32'd10, 32'd25, -32'd15, 1'b0);

        check_alu("SUB: Identical operands yielding Zero",
                  ALU_SUB, 32'hA5A5_5A5A, 32'hA5A5_5A5A, 32'h0000_0000, 1'b1);

        check_alu("SUB: Underflow Boundary (0 - 1)",
                  ALU_SUB, 32'h0000_0000, 32'h0000_0001, 32'hFFFF_FFFF, 1'b0);

        check_alu("SUB: MIN_INT - 1 wrap to MAX_INT",
                  ALU_SUB, 32'h8000_0000, 32'h0000_0001, 32'h7FFF_FFFF, 1'b0);

        // -------------------------------------------------------------
        // Group 3: AND Operations
        // -------------------------------------------------------------
        check_alu("AND: General bitwise masking",
                  ALU_AND, 32'h1234_5678, 32'h0000_FFFF, 32'h0000_5678, 1'b0);

        check_alu("AND: Identity with ALL_ONES",
                  ALU_AND, 32'hCAFE_BABE, 32'hFFFF_FFFF, 32'hCAFE_BABE, 1'b0);

        check_alu("AND: With Zero operand",
                  ALU_AND, 32'hDEAD_BEEF, 32'h0000_0000, 32'h0000_0000, 1'b1);

        check_alu("AND: Orthogonal bit patterns (result Zero)",
                  ALU_AND, 32'hAAAA_AAAA, 32'h5555_5555, 32'h0000_0000, 1'b1);

        // -------------------------------------------------------------
        // Group 4: OR Operations
        // -------------------------------------------------------------
        check_alu("OR: General bitwise merge",
                  ALU_OR, 32'hF0F0_0000, 32'h0000_0F0F, 32'hF0F0_0F0F, 1'b0);

        check_alu("OR: Identity with Zero operand",
                  ALU_OR, 32'h1234_ABCD, 32'h0000_0000, 32'h1234_ABCD, 1'b0);

        check_alu("OR: Saturating with ALL_ONES",
                  ALU_OR, 32'h1234_5678, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 1'b0);

        check_alu("OR: Complementary patterns (yields ALL_ONES)",
                  ALU_OR, 32'hAAAA_AAAA, 32'h5555_5555, 32'hFFFF_FFFF, 1'b0);

        check_alu("OR: Both zero inputs (yields Zero)",
                  ALU_OR, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, 1'b1);

        // -------------------------------------------------------------
        // Group 5: XOR Operations
        // -------------------------------------------------------------
        check_alu("XOR: Alternating bit toggle",
                  ALU_XOR, 32'hFFFF_FFFF, 32'hF0F0_F0F0, 32'h0F0F_0F0F, 1'b0);

        check_alu("XOR: Identical operands yielding Zero",
                  ALU_XOR, 32'hFEED_FACE, 32'hFEED_FACE, 32'h0000_0000, 1'b1);

        check_alu("XOR: Identity with Zero operand",
                  ALU_XOR, 32'hBADC_0FFE, 32'h0000_0000, 32'hBADC_0FFE, 1'b0);

        check_alu("XOR: Boundary single bit toggle",
                  ALU_XOR, 32'h8000_0000, 32'h0000_0001, 32'h8000_0001, 1'b0);

        // -------------------------------------------------------------
        // Group 6: Undefined / Default Opcode Behavior
        // -------------------------------------------------------------
        check_alu("DEFAULT: Unmapped Opcode (yields 0, Zero=1)",
                  4'b1111, 32'h1234_5678, 32'h9876_5432, 32'h0000_0000, 1'b1);

        // -------------------------------------------------------------
        // Final Summary and Status Exit
        // -------------------------------------------------------------
        $display("==================================================================");
        $display("   ALU Verification Summary: Total=%0d | Passed=%0d | Failed=%0d",
                 test_count, pass_count, fail_count);
        $display("==================================================================");

        if (fail_count == 0) begin
            $display(">>> ALL ALU TESTS PASSED SUCCESSFULLY! <<<");
            $finish(0); // Clean exit status
        end else begin
            $display(">>> ALU TESTBENCH FAILED (%0d ERRORS) <<<", fail_count);
            $fatal(1, "Terminating with non-zero exit status due to verification failure.");
        end
    end

endmodule
