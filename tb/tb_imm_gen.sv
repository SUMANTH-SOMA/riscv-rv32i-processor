`timescale 1ns / 1ps

// =============================================================================
// Module: tb_imm_gen
// Project: RV32I RISC-V Processor (Stage 4)
// Description:
//   Self-checking verification testbench for RV32I Immediate Generator.
//   Verifies I, S, B, U, and J immediate extraction, sign-extension,
//   halfword alignment (bit 0 zeroing), U-type low 12-bit zero masking,
//   boundary limits, and invalid selector rejection.
// =============================================================================

module tb_imm_gen;

    // DUT Signals
    logic [31:0] instr;
    logic [2:0]  imm_src;
    logic [31:0] imm;

    // Selector Constants matching rtl/imm_gen.sv
    localparam logic [2:0] IMM_I = 3'b000;
    localparam logic [2:0] IMM_S = 3'b001;
    localparam logic [2:0] IMM_B = 3'b010;
    localparam logic [2:0] IMM_U = 3'b011;
    localparam logic [2:0] IMM_J = 3'b100;

    // Test Tracking
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;

    // Instantiate DUT
    imm_gen dut (
        .instr(instr),
        .imm_src(imm_src),
        .imm(imm)
    );

    // Self-checking task
    task check_imm(
        input string       test_name,
        input logic [2:0]  src,
        input logic [31:0] in_instr,
        input logic [31:0] exp_imm
    );
        begin
            test_count++;
            imm_src = src;
            instr   = in_instr;

            #1; // Propagation delay for combinational settling

            if (imm === exp_imm) begin
                pass_count++;
                $display("[PASS] Test %02d: %s | Src=%b Instr=0x%08h -> Imm=0x%08h",
                         test_count, test_name, src, in_instr, imm);
            end else begin
                fail_count++;
                $display("[FAIL] Test %02d: %s | Src=%b Instr=0x%08h",
                         test_count, test_name, src, in_instr);
                $display("       Expected: 0x%08h", exp_imm);
                $display("       Actual:   0x%08h", imm);
            end
        end
    endtask

    // Main Test Stimulus
    initial begin
        // Configure waveform dumping for GTKWave inspection
        $dumpfile("sim/imm_gen.vcd");
        $dumpvars(0, tb_imm_gen);

        $display("==================================================================");
        $display("   RV32I Immediate Generator Verification Testbench Started");
        $display("==================================================================");

        // -------------------------------------------------------------
        // Group 1: I-type Immediate Tests (imm_src = 3'b000)
        // -------------------------------------------------------------
        check_imm("I-type: Positive nominal (+42)",
                  IMM_I, 32'h02A0_0093, 32'h0000_002A);

        check_imm("I-type: Negative nominal (-12)",
                  IMM_I, 32'hFF40_0093, 32'hFFFF_FFF4);

        check_imm("I-type: Maximum positive boundary (+2047)",
                  IMM_I, 32'h7FF0_0093, 32'h0000_07FF);

        check_imm("I-type: Minimum negative boundary (-2048)",
                  IMM_I, 32'h8000_0093, 32'hFFFF_F800);

        check_imm("I-type: Zero immediate",
                  IMM_I, 32'h0000_0093, 32'h0000_0000);

        // -------------------------------------------------------------
        // Group 2: S-type Immediate Tests (imm_src = 3'b001)
        // -------------------------------------------------------------
        check_imm("S-type: Positive nominal (+100)",
                  IMM_S, 32'h0620_A223, 32'h0000_0064);

        check_imm("S-type: Negative nominal (-27)",
                  IMM_S, 32'hFE20_A2A3, 32'hFFFF_FFE5);

        check_imm("S-type: Maximum positive boundary (+2047)",
                  IMM_S, 32'h7E00_0FA3, 32'h0000_07FF);

        check_imm("S-type: Minimum negative boundary (-2048)",
                  IMM_S, 32'h8000_0023, 32'hFFFF_F800);

        // -------------------------------------------------------------
        // Group 3: B-type Offset Tests (imm_src = 3'b010)
        // -------------------------------------------------------------
        check_imm("B-type: Positive branch offset (+24, LSB=0)",
                  IMM_B, 32'h0000_0C63, 32'h0000_0018);

        check_imm("B-type: Negative branch offset (-16, LSB=0)",
                  IMM_B, 32'hFE00_08E3, 32'hFFFF_FFF0);

        check_imm("B-type: Maximum positive boundary (+4094, LSB=0)",
                  IMM_B, 32'h7E00_0FE3, 32'h0000_0FFE);

        check_imm("B-type: Minimum negative boundary (-4096, LSB=0)",
                  IMM_B, 32'h8000_0063, 32'hFFFF_F000);

        // -------------------------------------------------------------
        // Group 4: U-type Immediate Tests (imm_src = 3'b011)
        // -------------------------------------------------------------
        check_imm("U-type: Positive aligned (low 12 bits zeroed)",
                  IMM_U, 32'h1234_5037, 32'h1234_5000);

        check_imm("U-type: Instruction low bits masked out to zero",
                  IMM_U, 32'hABCD_EFFF, 32'hABCD_E000);

        check_imm("U-type: All upper bits set boundary",
                  IMM_U, 32'hFFFF_FFFF, 32'hFFFF_F000);

        // -------------------------------------------------------------
        // Group 5: J-type Jump Offset Tests (imm_src = 3'b100)
        // -------------------------------------------------------------
        check_imm("J-type: Positive jump offset (+2048, LSB=0)",
                  IMM_J, 32'h0010_006F, 32'h0000_0800);

        check_imm("J-type: Negative jump offset (-2, LSB=0)",
                  IMM_J, 32'hFFFF_F06F, 32'hFFFF_FFFE);

        check_imm("J-type: Maximum positive boundary (+1048574, LSB=0)",
                  IMM_J, 32'h7FFF_F06F, 32'h000F_FFFE);

        check_imm("J-type: Minimum negative boundary (-1048576, LSB=0)",
                  IMM_J, 32'h8000_006F, 32'hFFF0_0000);

        // -------------------------------------------------------------
        // Group 6: Invalid / Reserved Selector Tests
        // -------------------------------------------------------------
        check_imm("Invalid selector 3'b101 returns zero",
                  3'b101, 32'hFFFF_FFFF, 32'h0000_0000);

        check_imm("Invalid selector 3'b110 returns zero",
                  3'b110, 32'h1234_5678, 32'h0000_0000);

        check_imm("Invalid selector 3'b111 returns zero",
                  3'b111, 32'hDEAD_BEEF, 32'h0000_0000);

        // -------------------------------------------------------------
        // Summary & Exit Status
        // -------------------------------------------------------------
        $display("==================================================================");
        $display("   Immediate Generator Summary: Total=%0d | Passed=%0d | Failed=%0d",
                 test_count, pass_count, fail_count);
        $display("==================================================================");

        if (fail_count == 0) begin
            $display(">>> ALL IMMEDIATE GENERATOR TESTS PASSED SUCCESSFULLY! <<<");
            $finish(0);
        end else begin
            $display(">>> IMMEDIATE GENERATOR TESTBENCH FAILED (%0d ERRORS) <<<", fail_count);
            $fatal(1, "Terminating due to verification failure.");
        end
    end

endmodule
