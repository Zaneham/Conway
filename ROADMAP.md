# Roadmap

*"People. What a bunch of bastards."* — Roy, The IT Crowd

But RISC-V instructions? Those we can work with.

---

## Phase 1: Arithmetic ✓

The foundation. If you can't add numbers, you can't do anything.

- [x] **Immediate operations**: addi, slti, sltiu, xori, ori, andi, slli, srli, srai
- [x] **Register operations**: add, sub, sll, slt, sltu, xor, srl, sra, or, and
- [x] **Upper immediate**: lui, auipc

Status: **Complete.** Tests passing. Tea consumed.

---

## Phase 2: Memory ✓

Because registers alone won't get you far.

- [x] **Loads**: lb, lh, lw, ld (signed)
- [x] **Unsigned loads**: lbu, lhu, lwu
- [x] **Stores**: sb, sh, sw, sd
- [x] **Guest memory buffer**: 64KB sandbox for RISC-V programmes

Status: **Complete.** Sign extension working properly. More tea.

---

## Phase 3: Control Flow ✓

Where things get interesting. Branches and jumps.

- [x] **Conditional branches**: beq, bne, blt, bge, bltu, bgeu
- [x] **Unconditional jumps**: jal, jalr
- [x] **Basic block detection**: Stop translating at branch boundaries
- [x] **Branch target calculation**: PC-relative addressing
- [x] **Block caching**: 1024-entry cache with hash lookup
- [x] **Execute loop**: Run multiple blocks in sequence

Status: **Complete.** Full block caching implemented. The code is jumping about properly now.

---

## Phase 4: System ✓

The bits that make it actually useful.

- [x] **ECALL/EBREAK**: System call interface (exit syscall terminates execution)
- [x] **CSR instructions**: Control and status registers (stub returning 0 - we're a teapot)
- [x] **Fence instructions**: Memory ordering (NOPs on x86, as predicted)
- [x] **High register fix**: Displacement encoding for x16-x31 now uses 32-bit offsets

Status: **Complete.** The machine can now politely request to exit. Jolly good.

---

## Phase 5: ELF Loader ✓

Load actual RISC-V binaries instead of hand-coded test cases.

- [x] **ELF64 parser**: Read RISC-V executables (validates magic, class, endianness, machine type)
- [x] **Section loading**: Map PT_LOAD segments into guest memory
- [ ] **Symbol resolution**: For debugging output (deferred - not essential)
- [x] **Entry point detection**: Find where to start
- [x] **Real binary tests**: Cross-compiled with riscv64-unknown-linux-gnu-gcc via Docker

**Test Programs:**
- `simple.S`: Arithmetic (10+20+30=60) ✓
- `fib.S`: Fibonacci(10)=55 ✓

Status: **Complete.** We can now load and execute real cross-compiled RISC-V binaries. The dream is alive!

---

## Phase 6: Optimisation

Make it fast. Or at least faster.

- [x] **Block caching**: Don't re-translate the same code *(moved to Phase 3)*
- [x] **Block linking**: Patch exits to jump directly between blocks
- [ ] **Hot path detection**: Identify frequently-executed blocks
- [ ] **Register allocation**: Map hot RISC-V regs to x86 regs
- [ ] **Peephole optimisation**: Combine common instruction sequences

Status: **In progress.** Block caching and linking complete. Blocks now jump directly to their successors, skipping the dispatch loop. The Fibonacci loop is now faster than a caffeinated rabbit.

---

## Phase 7: Doom

The ultimate test.

- [ ] **Run Doom**: If it can run Doom, it's a proper computer
- [ ] **Framebuffer support**: Memory-mapped display output
- [ ] **Input handling**: Keyboard/mouse via memory-mapped I/O

Status: **The dream.** Every emulator must eventually run Doom. It is known.

---

## Stretch Goals

Things that would be lovely but aren't essential:

- [x] **M extension**: Multiply/divide instructions (MUL, MULH, MULHU, DIV, DIVU, REM, REMU)
- [ ] **A extension**: Atomic operations
- [ ] **F/D extensions**: Floating-point (single/double)
- [ ] **C extension**: Compressed instructions
- [~] **Linux syscall compatibility**: Basic syscalls working (read, write, exit, brk, mmap)
- [ ] **Self-hosting**: Translate a RISC-V build of Conway itself

---

## Philosophy

1. **Correctness first.** A slow correct answer beats a fast wrong one.
2. **Test everything.** If it's not tested, it's broken.
3. **Keep it simple.** Clever code is hard to debug.
4. **Document as you go.** Future you will thank present you.
5. **Have fun.** This is a hobby project, not a job.

---

*Last updated after Phase 5 completion. We can now load and execute real cross-compiled RISC-V ELF binaries - tested with simple arithmetic and Fibonacci programs compiled via Docker. Also discovered and vanquished a particularly sneaky bug where emit_load_rs1 was clobbering the immediate value in ADDI, XORI, ORI, and ANDI. The tea helped.*
