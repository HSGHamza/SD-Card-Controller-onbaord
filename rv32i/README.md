# RISC-V RV32I RTL to GDS

An in-progress Verilog implementation of a 32-bit RISC-V (RV32I) processor. The project is being developed from core RTL building blocks toward a complete ASIC-oriented flow: simulation, synthesis, place-and-route, and ultimately GDSII generation.

> **Project status: early development.** The repository currently contains the initial processor modules and a preliminary ALU. It does not yet include a fully integrated processor top level, testbench, synthesis flow, physical-design scripts, or generated GDSII. Treat the current RTL as work in progress rather than a verified CPU implementation.

## Current design scope

The current source tree establishes the main blocks needed by an RV32I datapath:

```text
Program Counter -> Instruction Memory -> Decoder
                                      |
                                      v
Register File -> Immediate Extension -> ALU -> Register Write-back
```

| File | Module | Current purpose |
| --- | --- | --- |
| `ProgramCounter.v` | `ProgramCounter` | Holds the starting implementation of a PC that advances by 4 bytes. |
| `instructionMemory.v` | `instructionMemory` | Starting point for instruction-memory storage and addressing. |
| `decoder.v` | `decoder` | Extracts instruction fields such as opcode, register indices, and function fields. |
| `RegFile.v` | `RegFile` | 32-register general-purpose register file with two read ports and one write port. |
| `immTo32.v` | `immTo32` | Sign-extends a 12-bit immediate to 32 bits. |
| `alu.v` | `RI_alu` | Preliminary arithmetic and logic unit for R-type and I-type instruction encodings. |
| `Datapath.v` | `Datapath` | Placeholder for integrating the processor blocks. |
| `ControlLogic.v` | `ControlLogic` | Placeholder for processor control logic. |

### ALU operations being implemented

`RI_alu` selects its second operand from either a register (R-type) or sign-extended immediate (I-type). Its current decode covers the following RV32I-style ALU operations:

- `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, and `AND`
- Immediate counterparts: `ADDI`, `SLLI`, `SLTI`, `SLTIU`, `XORI`, `SRLI`, `SRAI`, `ORI`, and `ANDI`

These operations describe the intended ALU behavior; they are not yet exercised through a complete, verified processor datapath.

## Repository layout

```text
.
├── alu.v
├── ControlLogic.v
├── Datapath.v
├── decoder.v
├── immTo32.v
├── instructionMemory.v
├── ProgramCounter.v
└── RegFile.v
```

## Getting started

### Prerequisites

Use a Verilog simulator such as [Icarus Verilog](https://steveicarus.github.io/iverilog/) or Verilator. A waveform viewer such as GTKWave is recommended once testbenches are added.

### Clone the repository

```bash
git clone https://github.com/HSGHamza/RISCV-RV32I-RTL-Tto-GDS.git
cd RISCV-RV32I-RTL-Tto-GDS
```

### Compile the standalone ALU module

The ALU is currently the most self-contained module. With Icarus Verilog installed, run:

```bash
iverilog -g2012 -s RI_alu -o ri_alu.vvp alu.v
```

A complete processor-level simulation command will be added once the top-level datapath and testbench are available.

## Development roadmap

- [x] Create initial RTL modules for PC, instruction memory, decode, register file, immediate extension, and ALU
- [x] Add preliminary R-type and I-type ALU operation decoding
- [ ] Complete and connect the `Datapath` top-level module
- [ ] Implement control signals and write-back selection in `ControlLogic`
- [ ] Add reset, branch/jump, load/store, and remaining RV32I instruction support
- [ ] Add directed and automated Verilog testbenches
- [ ] Run RTL linting and regression simulation
- [ ] Add synthesis constraints and scripts
- [ ] Complete place-and-route and generate GDSII

## Contributing

Contributions are welcome while the design is being built. Please keep new RTL synthesizable, use clear module interfaces, and include a focused testbench whenever a functional block is completed or changed.

Before opening a pull request, run the relevant simulation or lint checks and describe the instructions or behavior covered by the change.

## License

No license has been added yet. Until one is included, the repository is not offered under an explicit open-source license.
