# RV32I RISC-V Processor Core (Single-Cycle & 5-Stage Pipelined)

A synthesizable, fully-verified 32-bit RISC-V (RV32I Base Integer) processor implementation in SystemVerilog, featuring both a golden **single-cycle reference core** and a high-throughput **5-stage pipelined core** with hazard detection, data forwarding, and branch/jump redirection.

---

## Key Highlights & Architectural Overview

This repository demonstrates digital design and verification principles from architectural specification down to cycle-accurate microarchitectural verification:

- **Dual Architectures**:
  - **Single-Cycle CPU (`cpu.sv`)**: Serves as the cycle-per-instruction baseline ($CPI = 1.00$) and golden architectural reference.
  - **5-Stage Pipelined CPU (`cpu_pipeline.sv`)**: Classic RISC pipeline partitioned into Instruction Fetch (**IF**), Instruction Decode (**ID**), Execute (**EX**), Memory Access (**MEM**), and Writeback (**WB**).
- **Hazard Resolution & Interlocking**:
  - **Data Forwarding Unit (`forwarding_unit.sv`)**: Resolves Read-After-Write (RAW) data hazards by bypassing results from EX/MEM and MEM/WB stages to EX operands. Prioritizes EX/MEM over MEM/WB on overlapping destinations.
  - **Store-Data Forwarding**: Forwards updated register data directly into memory write data.
  - **Zero-Register Immunity**: Prevents illegal forwarding from destination register `x0`.
  - **Load-Use Hazard Detection (`hazard_unit.sv`)**: Detects load-use dependencies in ID/EX, freezes PC and IF/ID registers for 1 clock cycle, and injects a synchronous bubble (NOP) into ID/EX.
  - **Control Hazard Redirection & Flushing**: Resolves conditional branches and unconditional jumps in the EX stage. On taken branch or jump, redirects the program counter and synchronously flushes the two younger in-flight instructions in IF/ID and ID/EX.
- **Verification Coverage**:
  - **112 Directed SystemVerilog Assertions**: 29 single-cycle assertions + 83 pipelined assertions covering all instruction classes, corner cases, forwarding paths, and hazard combinations.
  - **Automated Comparative Benchmark Suite**: 4 workloads executing identically on both cores with bit-level register and memory state equivalence checks.

---

## Supported Instruction Set Architecture (RV32I Subset)

Based on the implemented instruction decoder (`control_unit.sv` & `alu_decoder.sv`) and ALU (`alu.sv`), the core supports the following RV32I base integer instructions:

| Instruction Type | Instructions Supported | Notes |
| :--- | :--- | :--- |
| **R-Type Arithmetic/Logic** | `ADD`, `SUB`, `AND`, `OR`, `XOR`, `SLL`, `SRL`, `SRA`, `SLT`, `SLTU` | Uses forwarded EX/MEM and MEM/WB operands |
| **I-Type Arithmetic/Logic** | `ADDI`, `ANDI`, `ORI`, `XORI`, `SLLI`, `SRLI`, `SRAI`, `SLTI`, `SLTIU` | Immediate sign/zero extension via `imm_gen.sv` |
| **Memory Access** | `LW`, `SW` | 32-bit word-aligned memory access |
| **Conditional Branches** | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` | Resolved in EX stage (signed and unsigned) |
| **Upper Immediates** | `LUI`, `AUIPC` | 20-bit upper immediate generation |
| **Unconditional Jumps** | `JAL`, `JALR` | Stores `PC+4` link address into `rd`, flushes pipeline |

---

## Repository Structure

```
riscv-rv32i/
├── .gitignore                     # Ignores sim/*.vvp, sim/*.vcd, temporary files
├── LICENSE                        # MIT License (Sumanth Soma, 2026)
├── README.md                      # Project documentation and reproduction guide
├── run_all.bat                    # Windows one-click regression & benchmark runner
├── run_all.sh                     # Linux / MSYS2 one-click Bash runner
├── docs/
│   └── stage10f_performance_benchmark_report.md # Full cycle-level benchmark report
├── rtl/                           # Synthesizable SystemVerilog modules
│   ├── alu.sv                     # 32-bit Arithmetic Logic Unit
│   ├── alu_decoder.sv             # Secondary ALU operation decoder
│   ├── control_unit.sv            # Main opcode decoder & control signals
│   ├── cpu.sv                     # Single-Cycle CPU top-level integration
│   ├── cpu_pipeline.sv            # 5-Stage Pipelined CPU top-level integration
│   ├── data_memory.sv             # Synchronous write, asynchronous read RAM
│   ├── forwarding_unit.sv         # Data hazard bypass & forwarding unit
│   ├── hazard_unit.sv             # Load-use hazard detector & stall generator
│   ├── imm_gen.sv                 # Immediate generator (I, S, B, U, J types)
│   ├── instruction_memory.sv      # Instruction ROM
│   ├── pipeline_registers.sv      # IF/ID, ID/EX, EX/MEM, MEM/WB stage registers
│   └── register_file.sv           # 32x32-bit register file (x0 hardwired to 0)
├── tb/                            # Self-checking SystemVerilog testbenches
│   ├── tb_alu.sv                  # ALU unit testbench
│   ├── tb_control_unit.sv         # Control unit testbench
│   ├── tb_data_memory.sv          # Data memory testbench
│   ├── tb_imm_gen.sv              # Immediate generator testbench
│   ├── tb_instruction_memory.sv   # Instruction memory testbench
│   ├── tb_register_file.sv        # Register file testbench
│   ├── tb_cpu.sv                  # 29-assertion single-cycle regression suite
│   ├── tb_cpu_pipeline.sv         # 83-assertion pipelined regression suite
│   └── tb_benchmark.sv            # Comparative performance benchmark suite
├── programs/                      # Assembly / machine code test listings
└── sim/                           # Simulation directory (contains .gitkeep)
```

---

## Microarchitecture Deep Dive

### 1. Data Forwarding Logic
To eliminate avoidable pipeline stalls on RAW dependencies, `forwarding_unit.sv` continuously inspects source registers in EX (`ex_rs1`, `ex_rs2`) against destination registers in MEM (`mem_rd`) and WB (`wb_rd`):
- **EX/MEM Forwarding Priority**: If both EX/MEM and MEM/WB target the same nonzero register, the younger result in EX/MEM takes precedence (`forward_a/b = 2'b10`).
- **MEM/WB Forwarding**: Selected when `wb_reg_write` is active and matches `ex_rs1/rs2` (`forward_a/b = 2'b01`).
- **Store-Data Forwarding**: Forwards the latest result directly to `mem_rs2_data` for memory write operations.
- **Architectural $x0$ Protection**: Regwrite assertions targeting `x0` are strictly ignored by forwarding multiplexers.

### 2. Load-Use Hazard Interlocking
When an instruction in ID reads from a register being loaded by an immediately preceding `LW` instruction in EX:
1. `hazard_unit.sv` asserts `load_use_hazard = 1`.
2. `stall_pc = 1` freezes the Program Counter.
3. `stall_if_id = 1` retains the instruction in the IF/ID register.
4. `flush_id_ex = 1` clears control signals in ID/EX, injecting a single-cycle bubble (NOP).
5. On the subsequent clock edge, the loaded data advances to MEM/WB and is forwarded to EX with zero lost data.

### 3. Branch & Jump Redirection & Flushing
All conditional branch evaluations and jump target calculations resolve in the **EX stage**:
- **Redirection**: On a taken branch or jump, `ex_redirect` asserts and supplies `ex_redirect_target` directly to the IF-stage PC multiplexer.
- **2-Cycle Flushing**: Both instructions currently in flight behind the branch (in IF/ID and ID/EX) are wrong-path instructions. The pipeline asserts `flush_if_id` and `flush_id_ex`, squashing their execution and suppressing all register and memory writebacks.

---

## Verification & Comparative Benchmarks

### Verification Summary
The design underwent rigorous verification using self-checking SystemVerilog assertions:
- **Single-Cycle CPU Regression (`tb/tb_cpu.sv`)**: **29/29 PASSED**
- **5-Stage Pipelined CPU Regression (`tb/tb_cpu_pipeline.sv`)**: **83/83 PASSED**
- **Comparative Benchmark Suite (`tb/tb_benchmark.sv`)**: **4/4 WORKLOADS PASSED** with 100% architectural register and data-memory state equivalence.

### Comparative Benchmark Results

The benchmark suite evaluates both cores running identical machine code programs with equivalent initial architectural states:

| Workload ID & Description | Instructions ($I$) | Single-Cycle ($C_{\text{single}}$) | Pipeline ($C_{\text{pipe}}$) | Pipeline CPI | Cycle Ratio ($C_{\text{single}} / C_{\text{pipe}}$) | State Equivalence |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **BENCH_ALU** (Arithmetic & RAW Forwarding) | 21 | 21 cycles | 25 cycles | **1.190** | **0.840x** | **100% Match (PASS)** |
| **BENCH_MEM** (Memory Access & Load-Use Stalls) | 18 | 18 cycles | 25 cycles | **1.389** | **0.720x** | **100% Match (PASS)** |
| **BENCH_BRANCH** (Loops & Control Hazards) | 23 | 23 cycles | 37 cycles | **1.609** | **0.622x** | **100% Match (PASS)** |
| **BENCH_COMPOSITE** (Array Accumulate & Max Search) | 34 | 34 cycles | 52 cycles | **1.529** | **0.654x** | **100% Match (PASS)** |

### Analytical Cycle Breakdown (Pipelined Core)
Every measured pipeline cycle exactly satisfies the physical cycle equation:
$$C_{\text{pipe}} = I + \text{Startup Fill (4)} + \text{Load-Use Stalls} + \text{Branch Flush Penalties}$$
- **BENCH_ALU**: $21 + 4 + 0 + 0 = \mathbf{25\text{ cycles}}$
- **BENCH_MEM**: $18 + 4 + 3 + 0 = \mathbf{25\text{ cycles}}$ (3 load-use bubbles)
- **BENCH_BRANCH**: $23 + 4 + 0 + 10 = \mathbf{37\text{ cycles}}$ (5 taken redirects $\times 2$ flush penalty)
- **BENCH_COMPOSITE**: $34 + 4 + 4 + 10 = \mathbf{52\text{ cycles}}$ (4 load-use stalls + 5 taken redirects $\times 2$)

> **Important Architectural Note on Cycle Speedup vs. Real-Time Speedup**:  
> The cycle ratio ($C_{\text{single}} / C_{\text{pipe}} < 1.0$) reflects that the single-cycle core completes every instruction in 1 cycle ($CPI = 1.00$), while the pipelined core incurs 4 startup fill cycles, load-use interlocks, and branch mispredict flushes ($CPI > 1.00$).  
> These metrics represent **simulation cycle-count comparisons, NOT measured silicon or wall-clock execution speedup**. In physical hardware, pipelining dramatically reduces critical path delay, enabling substantially higher clock frequencies ($f_{\text{max}}$). Because this repository does not include synthesis or Static Timing Analysis (STA) data, real-time speedup is classified as **unmeasured / theoretical**.

---

## Reproducing Results

### Prerequisites
- **Icarus Verilog** (v12.0 or v13.0+ with `-g2012` SystemVerilog support)
- **GTKWave** (v3.3+ for viewing waveform dumpfiles)
- **OS**: Windows 11 (Command Prompt / PowerShell / MSYS2) or Linux / macOS

### One-Click Execution
- **Windows (Command Prompt / PowerShell)**:
  ```cmd
  run_all.bat
  ```
- **Linux / MSYS2 / Git Bash**:
  ```bash
  chmod +x run_all.sh
  ./run_all.sh
  ```

### Manual Compile & Run Commands
1. **Single-Cycle Regression (29 Assertions)**:
   ```cmd
   iverilog -g2012 -o sim/tb_cpu.vvp rtl/alu.sv rtl/register_file.sv rtl/imm_gen.sv rtl/control_unit.sv rtl/instruction_memory.sv rtl/data_memory.sv rtl/alu_decoder.sv rtl/cpu.sv tb/tb_cpu.sv
   vvp sim/tb_cpu.vvp
   ```
2. **Pipelined Regression (83 Assertions)**:
   ```cmd
   iverilog -g2012 -o sim/tb_cpu_pipeline.vvp rtl/alu.sv rtl/register_file.sv rtl/imm_gen.sv rtl/control_unit.sv rtl/instruction_memory.sv rtl/data_memory.sv rtl/alu_decoder.sv rtl/pipeline_registers.sv rtl/forwarding_unit.sv rtl/hazard_unit.sv rtl/cpu_pipeline.sv tb/tb_cpu_pipeline.sv
   vvp sim/tb_cpu_pipeline.vvp
   ```
3. **Comparative Benchmark Suite**:
   ```cmd
   iverilog -g2012 -o sim/tb_benchmark.vvp rtl/alu.sv rtl/register_file.sv rtl/imm_gen.sv rtl/control_unit.sv rtl/instruction_memory.sv rtl/data_memory.sv rtl/alu_decoder.sv rtl/pipeline_registers.sv rtl/forwarding_unit.sv rtl/hazard_unit.sv rtl/cpu.sv rtl/cpu_pipeline.sv tb/tb_benchmark.sv
   vvp sim/tb_benchmark.vvp
   ```

### Viewing Waveforms in GTKWave
All testbenches generate standard VCD dumpfiles under `sim/`:
```cmd
gtkwave sim/cpu_pipeline.vcd
gtkwave sim/benchmark.vcd
```
Key signals to inspect in `cpu_pipeline.vcd`:
- `u_pipe_cpu/if_pc`, `u_pipe_cpu/pipe_mem_wb/wb_pc` (Instruction progress)
- `u_pipe_cpu/forward_a`, `u_pipe_cpu/forward_b` (Forwarding multiplexer selects)
- `u_pipe_cpu/load_use_hazard`, `u_pipe_cpu/stall_pc` (Load-use interlock detection)
- `u_pipe_cpu/ex_redirect`, `u_pipe_cpu/flush_if_id`, `u_pipe_cpu/flush_id_ex` (Branch flush controls)

---

## Limitations & Future Work

- **Official Compliance Suite**: While 112 targeted assertions verify functional correctness across all supported instructions and hazard scenarios, the core has not yet been executed against the official `riscv-tests` architectural compliance suite.
- **Physical Synthesis & STA**: Logic synthesis, standard-cell mapping (e.g., using OpenROAD / Yosys or commercial EDA tools), and Static Timing Analysis (STA) have not been run; clock frequency ($f_{\text{max}}$) and area numbers remain uncharacterized.
- **Memory Subsystem**: Instruction and data memories currently model single-cycle SRAMs; cache hierarchies (L1 I-cache / D-cache) and bus protocols (AXI4-Lite / Wishbone) are future extensions.
- **Privileged Architecture & Exceptions**: Trap handling, CSR registers, and interrupts (M-mode) are not yet implemented.

---

## License

This project is open-source hardware licensed under the [MIT License](LICENSE).  
Copyright (c) 2026 Sumanth Soma.
