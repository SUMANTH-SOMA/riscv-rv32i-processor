`timescale 1ns / 1ps

// =============================================================================
// Module: tb_data_memory
// Project: RV32I RISC-V Processor (Stage 7)
// Description:
//   Self-checking verification testbench for simulation Data Memory.
//   Verifies:
//     1. Initial zero reads.
//     2. Write and readback at address zero.
//     3. Multiple independent word addresses.
//     4. mem_write=0 write suppression.
//     5. mem_read=0 zero forcing.
//     6. Unaligned read rejection and write suppression.
//     7. Out-of-range read rejection and write suppression.
//     8. Multi-cycle data persistence.
//     9. Simultaneous read and write behavior (old data before edge, new after).
// =============================================================================

module tb_data_memory;

    localparam int WORDS = 256;

    // DUT Clock and Control Signals
    logic        clk;
    logic        mem_read;
    logic        mem_write;
    logic [31:0] addr;
    logic [31:0] write_data;
    logic [31:0] read_data;

    // Test Tracking
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;

    // Instantiate DUT
    data_memory #(
        .WORDS(WORDS)
    ) dut (
        .clk(clk),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .addr(addr),
        .write_data(write_data),
        .read_data(read_data)
    );

    // 100 MHz System Clock (Period = 10ns)
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Helper task to execute a synchronous write
    task write_mem(input logic [31:0] in_addr, input logic [31:0] in_data);
        begin
            @(negedge clk);
            mem_write  = 1'b1;
            addr       = in_addr;
            write_data = in_data;
            @(posedge clk);
            #1; // Hold time past posedge
            mem_write  = 1'b0;
        end
    endtask

    // Helper task to verify a combinational read
    task check_read(
        input string       test_name,
        input logic        in_mem_read,
        input logic [31:0] in_addr,
        input logic [31:0] exp_data
    );
        begin
            test_count++;
            mem_read = in_mem_read;
            addr     = in_addr;

            #1; // Propagation delay for combinational read

            if (read_data === exp_data) begin
                pass_count++;
                $display("[PASS] Test %02d: %-42s | ReadEn=%b Addr=0x%08h -> ReadData=0x%08h",
                         test_count, test_name, in_mem_read, in_addr, read_data);
            end else begin
                fail_count++;
                $display("[FAIL] Test %02d: %s | ReadEn=%b Addr=0x%08h",
                         test_count, test_name, in_mem_read, in_addr);
                $display("       Expected: 0x%08h", exp_data);
                $display("       Actual:   0x%08h", read_data);
            end
        end
    endtask

    // Main Test Stimulus
    initial begin
        // Configure waveform dump for GTKWave inspection
        $dumpfile("sim/data_memory.vcd");
        $dumpvars(0, tb_data_memory);

        // Signal initialization
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        addr       = 32'h0000_0000;
        write_data = 32'h0000_0000;

        @(negedge clk);

        $display("==========================================================================================");
        $display("   RV32I Data Memory Verification Testbench Started");
        $display("==========================================================================================");

        // -------------------------------------------------------------
        // Test Group 1: Initial Zero Reads
        // -------------------------------------------------------------
        check_read("Initial zero read at Addr 0",
                   1'b1, 32'd0, 32'h0000_0000);

        check_read("Initial zero read at Addr 4",
                   1'b1, 32'd4, 32'h0000_0000);

        check_read("Initial zero read at Addr 1020",
                   1'b1, 32'd1020, 32'h0000_0000);

        // -------------------------------------------------------------
        // Test Group 2: Write Then Readback at Address Zero
        // -------------------------------------------------------------
        write_mem(32'd0, 32'hDEAD_BEEF);
        check_read("Write & readback at Addr 0 (0xDEADBEEF)",
                   1'b1, 32'd0, 32'hDEAD_BEEF);

        // -------------------------------------------------------------
        // Test Group 3: Multiple Independent Addresses
        // -------------------------------------------------------------
        write_mem(32'd4,    32'h1111_2222);
        write_mem(32'd8,    32'h3333_4444);
        write_mem(32'd12,   32'h5555_6666);
        write_mem(32'd1020, 32'hA5A5_5A5A); // Last word index 255

        check_read("Readback independent Word 1 (Addr 4)",
                   1'b1, 32'd4, 32'h1111_2222);

        check_read("Readback independent Word 2 (Addr 8)",
                   1'b1, 32'd8, 32'h3333_4444);

        check_read("Readback independent Word 3 (Addr 12)",
                   1'b1, 32'd12, 32'h5555_6666);

        check_read("Readback independent Word 255 (Addr 1020)",
                   1'b1, 32'd1020, 32'hA5A5_5A5A);

        // Re-verify address 0 was not corrupted
        check_read("Integrity check: Addr 0 retains 0xDEADBEEF",
                   1'b1, 32'd0, 32'hDEAD_BEEF);

        // -------------------------------------------------------------
        // Test Group 4: mem_write=0 Write Suppression
        // -------------------------------------------------------------
        @(negedge clk);
        mem_write  = 1'b0;
        addr       = 32'd4;
        write_data = 32'hFFFF_FFFF;
        @(posedge clk);
        #1;
        check_read("Write disabled (mem_write=0): Addr 4 protected",
                   1'b1, 32'd4, 32'h1111_2222);

        // -------------------------------------------------------------
        // Test Group 5: mem_read=0 Forces Output Zero
        // -------------------------------------------------------------
        check_read("mem_read=0 forces output zero at Addr 4",
                   1'b0, 32'd4, 32'h0000_0000);

        check_read("mem_read=0 forces output zero at Addr 0",
                   1'b0, 32'd0, 32'h0000_0000);

        // -------------------------------------------------------------
        // Test Group 6: Unaligned Read and Write Behavior
        // -------------------------------------------------------------
        // Attempt unaligned write to Addr 1, 2, 3 (within Word 0)
        write_mem(32'd1, 32'hCAFE_BABE);
        write_mem(32'd2, 32'hCAFE_BABE);
        write_mem(32'd3, 32'hCAFE_BABE);

        // Word 0 must remain 0xDEADBEEF
        check_read("Unaligned write ignored: Word 0 unchanged",
                   1'b1, 32'd0, 32'hDEAD_BEEF);

        // Unaligned reads must return zero
        check_read("Unaligned read at Addr 1 rejected (returns 0)",
                   1'b1, 32'd1, 32'h0000_0000);

        check_read("Unaligned read at Addr 2 rejected (returns 0)",
                   1'b1, 32'd2, 32'h0000_0000);

        check_read("Unaligned read at Addr 3 rejected (returns 0)",
                   1'b1, 32'd3, 32'h0000_0000);

        check_read("Unaligned read at Addr 5 rejected (returns 0)",
                   1'b1, 32'd5, 32'h0000_0000);

        // -------------------------------------------------------------
        // Test Group 7: Out-of-Range Read and Write Behavior
        // -------------------------------------------------------------
        // Attempt writes to addresses beyond allocated 256 words (1024 bytes)
        write_mem(32'd1024,       32'h9999_9999); // Word 256
        write_mem(32'd1028,       32'h9999_9999); // Word 257
        write_mem(32'h0001_0000, 32'h9999_9999); // High address

        check_read("Out-of-range read at Addr 1024 (Word 256) returns 0",
                   1'b1, 32'd1024, 32'h0000_0000);

        check_read("Out-of-range read at Addr 1028 (Word 257) returns 0",
                   1'b1, 32'd1028, 32'h0000_0000);

        check_read("Out-of-range read at Addr 0x00010000 returns 0",
                   1'b1, 32'h0001_0000, 32'h0000_0000);

        check_read("Out-of-range read at top space 0xFFFFFFFC returns 0",
                   1'b1, 32'hFFFF_FFFC, 32'h0000_0000);

        // -------------------------------------------------------------
        // Test Group 8: Data Persistence Across Idle Cycles
        // -------------------------------------------------------------
        mem_write = 1'b0;
        mem_read  = 1'b0;
        repeat (5) @(posedge clk);
        #1;

        check_read("Persistence check: Addr 0 retained after 5 idle cycles",
                   1'b1, 32'd0, 32'hDEAD_BEEF);

        check_read("Persistence check: Addr 8 retained after 5 idle cycles",
                   1'b1, 32'd8, 32'h3333_4444);

        check_read("Persistence check: Addr 1020 retained after 5 idle cycles",
                   1'b1, 32'd1020, 32'hA5A5_5A5A);

        // -------------------------------------------------------------
        // Test Group 9: Simultaneous Read and Write Controls
        // -------------------------------------------------------------
        // Address 16 currently has 0x00000000.
        // Setup simultaneous read and write:
        // mem_read=1 and mem_write=1 at Addr 16 with write_data=0x7777_8888.
        @(negedge clk);
        addr       = 32'd16;
        write_data = 32'h7777_8888;
        mem_read   = 1'b1;
        mem_write  = 1'b1;
        #1;

        // Prior to clock edge: combinational read reflects old memory state (0x0)
        test_count++;
        if (read_data === 32'h0000_0000) begin
            pass_count++;
            $display("[PASS] Test %02d: Simultaneous R/W: Pre-edge reads old data (0x00000000)",
                     test_count);
        end else begin
            fail_count++;
            $display("[FAIL] Test %02d: Simultaneous R/W: Pre-edge expected 0x00000000, got 0x%08h",
                     test_count, read_data);
        end

        // Trigger clock edge for synchronous write
        @(posedge clk);
        #1; // Settling time

        // Following clock edge: memory is updated, combinational read immediately reflects new data
        test_count++;
        if (read_data === 32'h7777_8888) begin
            pass_count++;
            $display("[PASS] Test %02d: Simultaneous R/W: Post-edge reads new data (0x77778888)",
                     test_count);
        end else begin
            fail_count++;
            $display("[FAIL] Test %02d: Simultaneous R/W: Post-edge expected 0x77778888, got 0x%08h",
                     test_count, read_data);
        end

        // Deassert controls
        mem_read  = 1'b0;
        mem_write = 1'b0;

        // -------------------------------------------------------------
        // Summary & Exit Status
        // -------------------------------------------------------------
        $display("==========================================================================================");
        $display("   Data Memory Summary: Total=%0d | Passed=%0d | Failed=%0d",
                 test_count, pass_count, fail_count);
        $display("==========================================================================================");

        if (fail_count == 0) begin
            $display(">>> ALL DATA MEMORY TESTS PASSED SUCCESSFULLY! <<<");
            $finish(0);
        end else begin
            $display(">>> DATA MEMORY TESTBENCH FAILED (%0d ERRORS) <<<", fail_count);
            $fatal(1, "Terminating due to verification failure.");
        end
    end

endmodule
