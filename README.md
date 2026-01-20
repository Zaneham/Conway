# Conway

A RISC-V to x86-64 dynamic binary translator that passes **100% of the official RISC-V compliance tests**.

## Quick Start

```bash
# Clone
git clone https://github.com/Zaneham/Conway.git
cd Conway

# Build (Windows)
build.bat

# Build (Linux)
make linux

# Run
./bin/conway examples/hello.elf
```

Output:
```
Hello from RISC-V!
```

That's a real RISC-V ELF binary running on your x86-64 machine.

## Compliance

Conway passes the **official RISC-V Architecture Compliance Test Suite**.

| Extension | Tests | Status |
|-----------|-------|--------|
| **I** - Base Integer | 50 | ALL PASS |
| **M** - Multiply/Divide | 13 | ALL PASS |
| **A** - Atomics | 18 | ALL PASS |
| **C** - Compressed | 33 | ALL PASS |
| **F** - Single-precision FP | 18 | ALL PASS |
| **D** - Double-precision FP | 27 | ALL PASS |
| **TOTAL** | **159** | **100%** |

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

## Why Assembly?

A reasonable question. We have an unreasonable answer.

Every other binary translator project trusts the compiler. The compiler is a very sophisticated piece of software that makes very sophisticated decisions. Sometimes these decisions are "I will now spill your hot register to memory because Mercury is in retrograde" or "I have detected a loop. I will unroll it. I will not tell you how much." You cannot argue with the compiler. The compiler has a computer science degree and knows what it is doing. The compiler is lying.

When you write the translator in assembly, you make all the decisions. This means when something breaks at 3am, it is your fault. This is actually better. When the compiler breaks something at 3am, it is still your fault, but you also cannot find it, because the compiler has Optimised.

There is something philosophically appropriate about writing a tool that converts assembly to assembly... in assembly. We are not "cutting out the middleman." We are acknowledging that the middleman was never our friend.

Also, Apple named their translator "Rosetta" and then locked it in a vault in Cupertino. We would like to remind Apple that the whole point of the Rosetta Stone was that people could *look at it*. It is in the British Museum. You can visit it. For free. On a Tuesday.

Anyway.

This is our stone. You are looking at it.

## Why not QEMU?

QEMU is faster. QEMU supports more architectures. QEMU has actual funding and a development team and probably a logo designed by someone who went to art school.

QEMU also fails compliance tests that Conway passes, but I'm sure they have their reasons.

I don't know what those reasons are. I didn't ask. It felt rude.

## Overview

Conway is a binary translator that dynamically converts RISC-V (RV64I) instructions to native x86-64 machine code. The translator operates at runtime, decoding RISC-V instructions and emitting equivalent x86-64 sequences.

It can load and execute real RISC-V ELF binaries. Yes, actual cross-compiled programmes. We were surprised too.

Please look at **ROADMAP.md** for more information on future plans!

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ ELF Loader  │────▶│ Translator  │────▶│ Block Cache │
│             │     │             │     │             │
└─────────────┘     └─────────────┘     └─────────────┘
                           │                   │
                           ▼                   ▼
                    ┌─────────────┐     ┌─────────────┐
                    │   Decode    │     │   Execute   │
                    │   & Emit    │     │    Loop     │
                    └─────────────┘     └─────────────┘
```

- **elf_loader.asm** - Parses ELF64 headers and loads PT_LOAD segments into guest memory
- **translator.asm** - The whole shebang: decode, emit, block cache, and execution loop

## Building

Good on you for being brave!

Requires NASM and a linker (ld or link.exe on Windows).

```bash
make
```

## Usage

```bash
./conway <riscv_binary>
```

## Cross-Compiling RISC-V Binaries

Don't have a RISC-V toolchain? Docker to the rescue:

```bash
# Compile a RISC-V programme
docker run --rm -v "$(pwd):/src" dockcross/linux-riscv64 bash -c \
  "riscv64-unknown-linux-gnu-gcc -static -nostdlib -march=rv64i -mabi=lp64 \
   -Wl,-Ttext=0x1000,--build-id=none -o /src/output.elf /src/input.S"
```

Test programmes live in `test/riscv/`. We've verified:
- `simple.S` - Arithmetic (10+20+30=60)
- `fib.S` - Fibonacci(10)=55

Both work. We checked twice.

## Supported Instructions

RV64IMAFDC - the full general-purpose instruction set:

- **Arithmetic**: ADD, SUB, AND, OR, XOR, SLT, SLTU
- **Shifts**: SLL, SRL, SRA
- **Immediate**: ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI
- **Loads**: LB, LH, LW, LD, LBU, LHU, LWU
- **Stores**: SB, SH, SW, SD
- **Branches**: BEQ, BNE, BLT, BGE, BLTU, BGEU
- **Jumps**: JAL, JALR
- **Upper Immediate**: LUI, AUIPC
- **M Extension**: MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
- **A Extension**: LR.W/D, SC.W/D, AMOSWAP, AMOADD, AMOAND, AMOOR, AMOXOR, AMOMIN, AMOMAX, AMOMINU, AMOMAXU
- **F Extension**: FLW, FSW, FADD.S, FSUB.S, FMUL.S, FDIV.S, FSQRT.S, FMIN.S, FMAX.S, FEQ.S, FLT.S, FLE.S, FCVT.W.S, FCVT.S.W
- **D Extension**: FLD, FSD, FADD.D, FSUB.D, FMUL.D, FDIV.D, FSQRT.D, FMIN.D, FMAX.D, FEQ.D, FLT.D, FLE.D, FCVT.W.D, FCVT.D.W
- **System**: ECALL, EBREAK, FENCE
- **CSR**: CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI (cycle, time, misa supported)

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
- Carl Sagan
