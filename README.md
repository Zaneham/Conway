# Conway

A RISC-V to x86-64 dynamic binary translator written in pure x86-64 assembly.

Named after Lynn Conway, who invented dynamic instruction scheduling. This project makes instructions flow between architectures. She figured out how to make them flow efficiently in the first place.

## What It Is

Conway loads a RISC-V ELF binary, translates it to native x86-64 machine code at runtime, and executes it. No interpreter loop. No LLVM. No compiler in the middle making decisions you didn't ask for.

It passes 100% of the official RISC-V compliance tests. Which is quite nifty really.

## What It Runs On

x86-64. Windows (MinGW) and Linux. The translator core is NASM assembly. The CLI and file I/O are a thin C wrapper that calls into the assembly.

## Compliance

| Extension | Tests | Status |
|-----------|-------|--------|
| **I** Base Integer | 50 | ALL PASS |
| **M** Multiply/Divide | 13 | ALL PASS |
| **A** Atomics | 18 | ALL PASS |
| **C** Compressed | 33 | ALL PASS |
| **F** Single-precision FP | 18 | ALL PASS |
| **D** Double-precision FP | 27 | ALL PASS |
| **TOTAL** | **159** | **100%** |

## Building

You need NASM and GCC (MinGW on Windows).

**Linux:**

```
make clean && make
```

**Windows:**

```
build-mingw.bat
```

## Usage

```
conway [options] <riscv_elf>
```

Options:

| Flag | What |
|------|------|
| `-h`, `--help` | Show usage |
| `-v`, `--verbose` | Print loader and execution details |
| `--max-blocks N` | Stop after translating N blocks (0 = unlimited) |
| `--dump-regs` | Print register file after execution |

Example:

```
$ ./bin/conway examples/hello.elf
Conway - RISC-V to x86-64 Binary Translator
Hello from RISC-V!
```

That's a real RISC-V ELF binary running on your x86-64 machine.

## Cross-Compiling RISC-V Binaries

```bash
docker run --rm -v "$(pwd):/src" dockcross/linux-riscv64 bash -c \
  "riscv64-unknown-linux-gnu-gcc -static -nostdlib -march=rv64i -mabi=lp64 \
   -Wl,-Ttext=0x1000,--build-id=none -o /src/output.elf /src/input.S"
```

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ ELF Loader  │────>│ Translator  │────>│ Block Cache │
└─────────────┘     └─────────────┘     └─────────────┘
                          │                    │
                          v                    v
                   ┌─────────────┐     ┌─────────────┐
                   │   Decode    │     │   Execute   │
                   │   & Emit    │     │    Loop     │
                   └─────────────┘     └─────────────┘
```

| File | What |
|------|------|
| `src/main.c` | C entry point. CLI, file I/O, memory allocation. |
| `include/conway.h` | C interface to the assembly core. |
| `src/translator.asm` | The whole shebang. Decode, emit, block cache, execution loop. |
| `src/elf_loader.asm` | Parses ELF64 headers, loads PT_LOAD segments into guest memory. |
| `src/platform_win.asm` | Windows syscall layer (WriteFile, VirtualProtect, etc). |
| `src/platform_linux.asm` | Linux syscall layer (write, mprotect, etc). |

## Supported Instructions

RV64IMAFDC. The full general-purpose set. See `include/rv_opcodes.inc` for the complete list.

## Register Mapping

| RISC-V | x86-64 | Notes |
|--------|--------|-------|
| x0 | - | Hardwired zero |
| x1-x7 | r8-r14 | Direct mapping |
| x8-x31 | Memory | Spill area |
| pc | r15 | Programme counter |

## Roadmap

See [ROADMAP.md](ROADMAP.md).

## License

Apache 2.0. See [LICENSE](LICENSE) for the full text.
