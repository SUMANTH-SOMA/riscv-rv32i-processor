`timescale 1ns / 1ps

// =============================================================================
// Module: tb_register_file
// Project: RV32I RISC-V Processor (Stage 3)
// Description:
//   Self-checking verification testbench for RV32I register file.
//   Verifies dual combinational read ports, single synchronous write port,
//   hardwired x0 zero-semantics, persistency, overwrite behavior, write-enable
//   gating, and boundary register addresses (x1 and x31).
// =============================================================================

module tb_register_file;

    // DUT Clock and Control Signals
    logic        clk;
    logic        we;
    logic [4:0]  raddr1;
    logic [4:0]  raddr2;
    logic [4:0]  waddr;
    logic [31:0] wdata;
    logic [31:0] rdata1;
    logic [31:0] rdata2;

    // Test Tracking
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;

    // Instantiate Device Under Test
    register_file dut (
        .clk(clk),
        .we(we),
        .raddr1(raddr1),
        .raddr2(raddr2),
        .waddr(waddr),
        .wdata(wdata),
        .rdata1(rdata1),
        .rdata2(rdata2)
    );

    // 100 MHz Clock Generator (Period = 10ns)
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Helper task to execute a synchronous write
    task write_reg(input logic [4:0] addr, input logic [31:0] data);
        begin
            @(negedge clk);
            we    = 1'b1;
            waddr = addr;
            wdata = data;
            @(posedge clk);
            #1; // Hold time past posedge
            we    = 1'b0;
        end
    endtask

    // Helper task for combinational dual-port read verification
    task check_read(
        input string       test_name,
        input logic [4:0]  rd_addr1,
        input logic [31:0] exp_data1,
        input logic [4:0]  rd_addr2,
        input logic [31:0] exp_data2
    );
        begin
            test_count++;
            raddr1 = rd_addr1;
            raddr2 = rd_addr2;
            #1; // Propagation delay for combinational read

            if ((rdata1 === exp_data1) && (rdata2 === exp_data2)) begin
                pass_count++;
                $display("[PASS] Test %02d: %s | Port1[x%0d]=0x%08h Port2[x%0d]=0x%08h",
                         test_count, test_name, rd_addr1, rdata1, rd_addr2, rdata2);
            end else begin
                fail_count++;
                $display("[FAIL] Test %02d: %s", test_count, test_name);
                $display("       Port 1: Addr=x%0d | Expected=0x%08h, Got=0x%08h",
                         rd_addr1, exp_data1, rdata1);
                $display("       Port 2: Addr=x%0d | Expected=0x%08h, Got=0x%08h",
                         rd_addr2, exp_data2, rdata2);
            end
        end
    endtask

    // Main Test Stimulus
    initial begin
        // Configure waveform dump
        $dumpfile("sim/register_file.vcd");
        $dumpvars(0, tb_register_file);

        // Signal initialization
        we     = 1'b0;
        raddr1 = 5'd0;
        raddr2 = 5'd0;
        waddr  = 5'd0;
        wdata  = 32'h0000_0000;

        // Allow clock to stabilize
        @(negedge clk);

        $display("==================================================================");
        $display("   RV32I Register File Verification Testbench Started");
        $display("==================================================================");

        // -------------------------------------------------------------
        // Test 1: Reading x0 returns zero on both ports
        // -------------------------------------------------------------
        check_read("Initial read of x0 returns 0 on both ports",
                   5'd0, 32'h0000_0000, 5'd0, 32'h0000_0000);

        // -------------------------------------------------------------
        // Test 2: Writing to x0 has no effect
        // -------------------------------------------------------------
        write_reg(5'd0, 32'hDEAD_BEEF);
        check_read("Write to x0 ignored (x0 remains zero on both ports)",
                   5'd0, 32'h0000_0000, 5'd0, 32'h0000_0000);

        // -------------------------------------------------------------
        // Test 3: Writing and reading a nonzero register (x5)
        // -------------------------------------------------------------
        write_reg(5'd5, 32'h1234_5678);
        check_read("Write to x5 and read via Port 1",
                   5'd5, 32'h1234_5678, 5'd0, 32'h0000_0000);

        // -------------------------------------------------------------
        // Test 4: Reading two different registers simultaneously (x5, x10)
        // -------------------------------------------------------------
        write_reg(5'd10, 32'hA5A5_5A5A);
        check_read("Simultaneous read: Port1=x5, Port2=x10",
                   5'd5, 32'h1234_5678, 5'd10, 32'hA5A5_5A5A);

        // Swap ports to ensure symmetry
        check_read("Simultaneous read (swapped ports): Port1=x10, Port2=x5",
                   5'd10, 32'hA5A5_5A5A, 5'd5, 32'h1234_5678);

        // -------------------------------------------------------------
        // Test 5: Updating an existing register (overwrite x5)
        // -------------------------------------------------------------
        write_reg(5'd5, 32'hCAFE_BABE);
        check_read("Overwrite x5 with new value (0xCAFEBABE)",
                   5'd5, 32'hCAFE_BABE, 5'd10, 32'hA5A5_5A5A);

        // -------------------------------------------------------------
        // Test 6: Register values persist when no write occurs across cycles
        // -------------------------------------------------------------
        repeat (5) @(posedge clk);
        #1;
        check_read("Persistency check: x5 and x10 unchanged after idle cycles",
                   5'd5, 32'hCAFE_BABE, 5'd10, 32'hA5A5_5A5A);

        // -------------------------------------------------------------
        // Test 7: Writing while we=0 does not change register contents
        // -------------------------------------------------------------
        @(negedge clk);
        we    = 1'b0;
        waddr = 5'd5;
        wdata = 32'hFFFF_FFFF;
        @(posedge clk);
        #1;
        check_read("Write disabled (we=0): x5 protected from overwrite",
                   5'd5, 32'hCAFE_BABE, 5'd10, 32'hA5A5_5A5A);

        // -------------------------------------------------------------
        // Test 8: Boundary register addresses x1 and x31
        // -------------------------------------------------------------
        write_reg(5'd1, 32'h1111_1111);
        check_read("Boundary register x1 written and verified",
                   5'd1, 32'h1111_1111, 5'd0, 32'h0000_0000);

        write_reg(5'd31, 32'h8888_8888);
        check_read("Boundary register x31 written and verified",
                   5'd31, 32'h8888_8888, 5'd1, 32'h1111_1111);

        // Simultaneous verification of both boundary registers
        check_read("Simultaneous boundary read: Port1=x1, Port2=x31",
                   5'd1, 32'h1111_1111, 5'd31, 32'h8888_8888);

        // Re-verify that x0 remained zero throughout all operations
        check_read("Final integrity verification: x0 strictly remains zero",
                   5'd0, 32'h0000_0000, 5'd0, 32'h0000_0000);

        // -------------------------------------------------------------
        // Summary & Exit Status
        // -------------------------------------------------------------
        $display("==================================================================");
        $display("   Register File Summary: Total=%0d | Passed=%0d | Failed=%0d",
                 test_count, pass_count, fail_count);
        $display("==================================================================");

        if (fail_count == 0) begin
            $display(">>> ALL REGISTER FILE TESTS PASSED SUCCESSFULLY! <<<");
            $finish(0);
        end else begin
            $display(">>> REGISTER FILE TESTBENCH FAILED (%0d ERRORS) <<<", fail_count);
            $fatal(1, "Terminating due to verification failure.");
        end
    end

endmodule
