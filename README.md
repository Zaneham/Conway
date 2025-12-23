# Conway

A RISC-V to x86-64 dynamic binary translator.

## Why "Conway"?

Named after Lynn Conway (1938-2024), who invented dynamic 
instruction scheduling, the technique that makes modern 
CPUs fast.

She transitioned in 1968, rebuilt her career from scratch, 
co-wrote the textbook that taught a generation how to design 
chips, rode motorcycles, and spent 37 years with the love of 
her life.

She passed away at 86 having changed the world.

This project is about making instructions flow between 
architectures. She figured out how to make them flow 
efficiently in the first place.

## Overview

Conway is a binary translator that dynamically converts RISC-V (RV64I) instructions to native x86-64 machine code. The translator operates at runtime, decoding RISC-V instructions and emitting equivalent x86-64 sequences.

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Decode    │────▶│  Dispatch   │────▶│    Emit     │
│  (decode)   │     │ (dispatch)  │     │   (emit)    │
└─────────────┘     └─────────────┘     └─────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │   Runtime   │
                    │  (runtime)  │
                    └─────────────┘
```

- **decode.asm** - Parses RISC-V instruction encoding, extracts opcode, registers, and immediates
- **dispatch.asm** - Routes decoded instructions to appropriate emission handlers
- **emit.asm** - Generates x86-64 machine code sequences
- **runtime.asm** - Manages execution context, register mapping, and memory

## Building

Requires NASM and a linker (ld or link.exe on Windows).

```bash
make
```

## Usage

```bash
./conway <riscv_binary>
```

## Supported Instructions

Currently targeting RV64I base integer instruction set:

- **Arithmetic**: ADD, SUB, AND, OR, XOR, SLT, SLTU
- **Shifts**: SLL, SRL, SRA
- **Immediate**: ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI
- **Loads**: LB, LH, LW, LD, LBU, LHU, LWU
- **Stores**: SB, SH, SW, SD
- **Branches**: BEQ, BNE, BLT, BGE, BLTU, BGEU
- **Jumps**: JAL, JALR
- **Upper Immediate**: LUI, AUIPC

## Register Mapping

RISC-V registers are mapped to x86-64 registers and a spill area:

| RISC-V | x86-64 | Notes |
|--------|--------|-------|
| x0     | -      | Hardwired zero |
| x1-x7  | r8-r14 | Direct mapping |
| x8-x31 | Memory | Spill area |
| pc     | r15    | Programme counter |

## Licence

Apache License 2.0. See [LICENSE](LICENSE) for details.

---

*"If you wish to make an apple pie from scratch, you must first invent the universe."*
— Carl Sagan
