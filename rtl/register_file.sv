`timescale 1ns / 1ps

// =============================================================================
// Module: register_file
// Project: RV32I RISC-V Processor (Stage 3)
// Description:
//   32-bit RV32I architectural integer register file.
//   - 32 general-purpose registers (x0 to x31), each 32 bits wide.
//   - Two independent asynchronous / combinational read ports (raddr1, raddr2).
//   - One synchronous write port (waddr, wdata, we) sampled on posedge clk.
//   - Hardware-enforced zero register (x0):
//       * Reads to x0 always yield 32'h0000_0000.
//       * Writes to x0 are ignored.
//   - Registers x1 through x31 store state across cycles until updated.
// =============================================================================

module register_file (
    input  logic        clk,        // Positive-edge system clock
    input  logic        we,         // Synchronous write enable (active high)
    input  logic [4:0]  raddr1,     // Read port 1 register address (rs1: 0..31)
    input  logic [4:0]  raddr2,     // Read port 2 register address (rs2: 0..31)
    input  logic [4:0]  waddr,      // Write port destination address (rd: 0..31)
    input  logic [31:0] wdata,      // 32-bit write data
    output logic [31:0] rdata1,     // Read port 1 data output
    output logic [31:0] rdata2      // Read port 2 data output
);

    // 32 architectural 32-bit registers
    logic [31:0] regs [0:31];

    // -------------------------------------------------------------------------
    // Simulation Initialization:
    // Initialize registers to 0 for deterministic, clean simulation state.
    // NOTE: This initial block is a behavioral simulation convenience and does
    // NOT represent physical ASIC power-on reset state, which is undefined
    // unless an explicit hardware reset network or power-on-reset is synthesized.
    // -------------------------------------------------------------------------
    initial begin
        for (int i = 0; i < 32; i++) begin
            regs[i] = 32'h0000_0000;
        end
    end

    // -------------------------------------------------------------------------
    // Synchronous Write Port:
    // Writes occur on the rising edge of clk when write-enable (we) is asserted.
    // Hardware enforces that x0 (address 0) is never written.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (we && (waddr != 5'd0)) begin
            regs[waddr] <= wdata;
        end
    end

    // -------------------------------------------------------------------------
    // Asynchronous / Combinational Read Ports:
    // Read operations are immediate and independent.
    // x0 is hardwired to always return 32'h0000_0000 regardless of internal array.
    // -------------------------------------------------------------------------
    assign rdata1 = (raddr1 == 5'd0) ? 32'h0000_0000 : regs[raddr1];
    assign rdata2 = (raddr2 == 5'd0) ? 32'h0000_0000 : regs[raddr2];

endmodule
