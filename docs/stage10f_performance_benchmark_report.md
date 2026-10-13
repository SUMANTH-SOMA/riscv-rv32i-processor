# Stage 10F — RV32I Comparative Performance Benchmark Report (Corrected)

## 1. Overview & Objectives
This report details the corrected implementation, methodology, and verified simulation results of **Stage 10F — Performance Benchmarking**, comparing the frozen RV32I Single-Cycle CPU (`rtl/cpu.sv`) against the 5-Stage Pipelined RV32I CPU (`rtl/cpu_pipeline.sv`).

All four workloads were executed with 100% equivalent initial architectural state, verified machine instruction encodings, and rigorous end-of-test state equivalence assertions across all 32 registers (`x0`–`x31`) and all data memory words.

---

## 2. Experimental Methodology & Measurement Conventions

### 2.1 Measurement Boundaries & Conventions
- **Start Convention**:
  - Both CPUs start synchronously from reset deassertion (`rst_n` transitioning low $\to$ high).
  - Cycle counters begin at cycle 0 while instruction at `PC = 0x00000000` is fetched.
- **Stop & Drain Convention**:
  - Each workload terminates with a self-loop halt instruction: `beq x0, x0, 0` at a predetermined `halt_pc`.
  - **Single-Cycle CPU**: Execution loop stops when `pc_out == halt_pc`. Because `pc` updates on the rising edge, the halt instruction is retired in the final cycle before termination.
  - **Pipelined CPU**: Execution loop stops when `pipe_mem_wb.wb_pc == halt_pc`. This guarantees that the halt instruction has retired into the Writeback (WB) stage and every preceding instruction has fully committed to architectural registers and data memory.
- **Retired Instruction Count ($I$)**:
  - Dynamically retired architectural instructions that successfully committed to architectural state (including the terminal halt instruction).
  - Flushed wrong-path instructions and injected stall bubbles are strictly excluded from $I$.
- **Flush-Penalty Accounting Correction**:
  - In previous audit findings, when the terminal `beq x0, x0, 0` reached the EX stage, its condition ($x0 == x0$) evaluated as taken, which asserted `ex_redirect` and added $+2$ false flush penalty cycles to the table.
  - The accounting logic has been corrected to monitor `(ex_redirect && (ex_pc !== halt_pc))`.
  - This ensures that only **algorithm-induced pipeline flushes** are counted in the penalty breakdown table, reflecting the true penalty added by control hazards.
- **Formulas**:
  $$\text{CPI} = \frac{\text{Elapsed Clock Cycles}}{\text{Retired Instructions}}$$
  $$\text{Cycle-Count Speedup} = \frac{\text{Single-Cycle Elapsed Cycles}}{\text{Pipelined Elapsed Cycles}} = \frac{C_{\text{single}}}{C_{\text{pipe}}}$$
  $$\text{Analytical Pipeline Cycles: } C_{\text{pipe}} = I + \text{Fill Cycles} + \text{Load-Use Stalls} + \text{Branch Flush Penalties}$$

---

## 3. Workload Suite

| Workload ID | Name | Dynamic Instructions | Focus / Characterization |
| :--- | :--- | :---: | :--- |
| **BENCH_ALU** | Arithmetic & Forwarding | 21 | Pure ALU arithmetic/logic with dense RAW hazards exercising distance-1 (EX/MEM $\to$ EX) and distance-2 (MEM/WB $\to$ EX) forwarding. Zero stalls, zero algorithm flushes. |
| **BENCH_MEM** | Load/Store & Stalling | 18 | Alternating data memory writes, reads, and 3 back-to-back load-use hazards each triggering a 1-cycle pipeline interlock stall + store-data forwarding. Zero algorithm flushes. |
| **BENCH_BRANCH** | Control Hazards & Loops | 23 | Iterative loop (5 iterations) using `blt` (4 taken backwards, 1 not-taken fallthrough) + unconditional `jal` jump over error trap. Incurs 2-cycle flush penalty per taken redirect (5 taken redirects = 10 penalty cycles). |
| **BENCH_COMPOSITE** | Array Accumulate & Max Search | 34 | Realistic algorithm: loops through a 4-element array `[12, 45, 23, 38]` in memory, computes sum ($118$) and finds maximum element ($45$). Combines memory loads, arithmetic, load-use stalls, conditional forward/backward branches, and stores. |

---

## 4. Benchmark Empirical Results

### 4.1 Performance Summary Table (Measured from Simulation)

| Workload Description | Instructions ($I$) | Single-Cycle Cycles ($C_{\text{single}}$) | Pipeline Cycles ($C_{\text{pipe}}$) | $\text{CPI}_{\text{single}}$ | $\text{CPI}_{\text{pipe}}$ | Cycle Speedup ($S_{\text{cycle}}$) | Equivalence Verification |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **BENCH_ALU** | 21 | 21 | 25 | 1.000 | 1.190 | **0.840x** | **PASS** (Identical) |
| **BENCH_MEM** | 18 | 18 | 25 | 1.000 | 1.389 | **0.720x** | **PASS** (Identical) |
| **BENCH_BRANCH** | 23 | 23 | 37 | 1.000 | 1.609 | **0.622x** | **PASS** (Identical) |
| **BENCH_COMPOSITE** | 34 | 34 | 52 | 1.000 | 1.529 | **0.654x** | **PASS** (Identical) |

### 4.2 Pipeline Overhead & Penalty Breakdown (Corrected Accounting)

| Workload | Fill Cycles (Startup) | Stall Cycles (Load-Use) | Flush Penalty (Algorithm) | EX/MEM Forwards | MEM/WB Forwards | Total Pipeline Cycles ($C_{\text{pipe}}$) | Analytical Match |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **BENCH_ALU** | 4 | 0 | 0 | 10 | 5 | **25** | $21 + 4 + 0 + 0 = 25$ |
| **BENCH_MEM** | 4 | 3 | 0 | 6 | 4 | **25** | $18 + 4 + 3 + 0 = 25$ |
| **BENCH_BRANCH** | 4 | 0 | 10 (5 redirects $\times 2$) | 6 | 7 | **37** | $23 + 4 + 0 + 10 = 37$ |
| **BENCH_COMPOSITE** | 4 | 4 | 10 (5 redirects $\times 2$) | 4 | 4 | **52** | $34 + 4 + 4 + 10 = 52$ |

*Every workload's measured cycle count exactly satisfies $C_{\text{pipe}} = I + \text{Fill} + \text{Stall} + \text{Flush}$.*

---

## 5. Architectural State Equivalence & Algorithm Correctness Verification

### 5.1 Composite Algorithm Mathematical & Functional Verification
The previous immediate encoding defect in `BENCH_COMPOSITE` (where `0x0062DA63` encoded $+20$ instead of $+8$) was corrected to:
- `32'h0062_D463` $\implies$ `bge x5, x6, +8`
  - Opcode = `0x63` (B-type)
  - funct3 = `3'b101` (BGE)
  - rs1 = `5'b00101` (`x5`)
  - rs2 = `5'b00110` (`x6`)
  - Immediate = $+8$ (`0x0008`)

### 5.2 Dedicated Composite Assertions
The testbench verified the following explicit assertions after workload completion:
1. `u_single_cpu.reg_file.regs[4] == 118` && `u_pipe_cpu.reg_file.regs[4] == 118` (Accumulated Sum = $12 + 45 + 23 + 38 = 118$) $\implies$ **PASSED**
2. `u_single_cpu.reg_file.regs[5] == 45` && `u_pipe_cpu.reg_file.regs[5] == 45` (Maximum Element = $45$) $\implies$ **PASSED**
3. `u_single_cpu.reg_file.regs[2] == 4` && `u_pipe_cpu.reg_file.regs[2] == 4` (Loop Index = $4$) $\implies$ **PASSED**
4. `u_single_cpu.dmem.mem[10] == 118` && `u_pipe_cpu.dmem.mem[10] == 118` (Memory Store of Sum) $\implies$ **PASSED**
5. `u_single_cpu.dmem.mem[11] == 45` && `u_pipe_cpu.dmem.mem[11] == 45` (Memory Store of Max) $\implies$ **PASSED**
6. Full architectural comparison across all 32 registers and 64 memory words: **0 mismatches**.

---

## 6. Cycle-Count Speedup vs. Real-Time (Wall-Clock) Speedup

### 6.1 Cycle-Count Speedup ($S_{\text{cycle}} < 1.0$)
In synchronous digital logic:
$$\text{Execution Time} = I \times \text{CPI} \times T_{clk}$$

- **Single-Cycle Processor**:
  - Completes every instruction in exactly 1 clock cycle: $\text{CPI}_{\text{single}} = 1.000$.
- **5-Stage Pipelined Processor**:
  - Incurs 4 startup fill cycles.
  - Incurs 1 bubble per load-use dependency interlock.
  - Incurs 2 wrong-path instruction flushes per taken branch or jump.
  - Consequently, $\text{CPI}_{\text{pipe}} > 1.000$ ($1.190 - 1.609$).
  - As a result, the raw cycle-count speedup $S_{\text{cycle}} = \frac{C_{\text{single}}}{C_{\text{pipe}}} < 1.0$.

### 6.2 Clock-Period Scaling Status: Unmeasured & Hypothetical
- In realistic physical hardware implementations, pipelining divides the single-cycle critical path into smaller segments, allowing the pipelined core to operate at a higher clock frequency ($f_{\text{pipe}} > f_{\text{single}}$).
- **Explicit Scope Limitation**:
  - The repository currently contains **no logic synthesis, standard-cell technology mapping, or Static Timing Analysis (STA)** data.
  - Therefore, **real-time wall-clock speedup cannot be claimed as an empirical result**.
  - Any frequency scaling factors (such as $3\times - 4\times$) are **strictly theoretical hypotheses** and remain **unmeasured** until synthesis and timing closure are performed in future stages.

---

## 7. Verification & Regression Status

### 7.1 Fresh Benchmark Run (`tb/tb_benchmark.sv`)
- **Compilation Command**:
  ```cmd
  iverilog -g2012 -o sim/tb_benchmark.vvp rtl/alu.sv rtl/register_file.sv rtl/imm_gen.sv rtl/control_unit.sv rtl/instruction_memory.sv rtl/data_memory.sv rtl/alu_decoder.sv rtl/pipeline_registers.sv rtl/forwarding_unit.sv rtl/hazard_unit.sv rtl/cpu.sv rtl/cpu_pipeline.sv tb/tb_benchmark.sv
  ```
- **Execution Command**:
  ```cmd
  vvp sim/tb_benchmark.vvp
  ```
- **Actual Exit Code**: `0`
- **Output**:
  ```
  [EQUIVALENCE CHECK PASSED] BENCH_ALU (Arithmetic & Forwarding): Architectural state identical across all registers & data memory.
  [EQUIVALENCE CHECK PASSED] BENCH_MEM (Load/Store & Stalling): Architectural state identical across all registers & data memory.
  [EQUIVALENCE CHECK PASSED] BENCH_BRANCH (Control Hazards & Loops): Architectural state identical across all registers & data memory.
  [EQUIVALENCE CHECK PASSED] BENCH_COMPOSITE (Array Accumulate & Max Search): Architectural state identical across all registers & data memory.
  [ASSERTION PASSED] Composite final sum is 118 across both cores.
  [ASSERTION PASSED] Composite final max is 45 across both cores.
  [ASSERTION PASSED] Composite final loop index is 4 across both cores.
  [ASSERTION PASSED] Composite stored memory holds Mem[10]=118, Mem[11]=45 across both cores.
  >>> ALL 4/4 COMPARATIVE PERFORMANCE BENCHMARKS PASSED WITH FULL ARCHITECTURAL EQUIVALENCE! <<<
  ```

### 7.2 Pipelined Regression Baseline (`tb/tb_cpu_pipeline.sv`)
- **Command**:
  ```cmd
  iverilog -g2012 -o sim/tb_cpu_pipeline.vvp rtl/alu.sv rtl/register_file.sv rtl/imm_gen.sv rtl/control_unit.sv rtl/instruction_memory.sv rtl/data_memory.sv rtl/alu_decoder.sv rtl/pipeline_registers.sv rtl/forwarding_unit.sv rtl/hazard_unit.sv rtl/cpu_pipeline.sv tb/tb_cpu_pipeline.sv
  vvp sim/tb_cpu_pipeline.vvp
  ```
- **Actual Exit Code**: `0`
- **Assertion Total**: **83/83 PASSED** (0 failures).

### 7.3 Single-Cycle Regression Baseline (`tb/tb_cpu.sv`)
- **Command**:
  ```cmd
  iverilog -g2012 -o sim/tb_cpu.vvp rtl/alu.sv rtl/register_file.sv rtl/imm_gen.sv rtl/control_unit.sv rtl/instruction_memory.sv rtl/data_memory.sv rtl/alu_decoder.sv rtl/cpu.sv tb/tb_cpu.sv
  vvp sim/tb_cpu.vvp
  ```
- **Actual Exit Code**: `0`
- **Assertion Total**: **29/29 PASSED** (0 failures).

### 7.4 Source File Integrity & Limitations
- **RTL Source Files**: 0 modified.
- **Existing Testbenches** (`tb_cpu.sv`, `tb_cpu_pipeline.sv`): 0 modified.
- **Modified Benchmark Files Only**: `tb/tb_benchmark.sv` and `docs/stage10f_performance_benchmark_report.md`.
- **Git Repository Limitation**: The directory `C:\Users\suman\.gemini\antigravity-ide\scratch\riscv-rv32i` is not an initialized Git repository (`fatal: not a git repository: .git`), so diff verification is confirmed via direct file hash/inspection.
