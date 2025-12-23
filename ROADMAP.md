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

## Phase 3: Control Flow

Where things get interesting. Branches and jumps.

- [ ] **Conditional branches**: beq, bne, blt, bge, bltu, bgeu
- [ ] **Unconditional jumps**: jal, jalr
- [ ] **Basic block detection**: Stop translating at branch boundaries
- [ ] **Branch target calculation**: PC-relative addressing

Status: **Not started.** This is where the real fun begins.

---

## Phase 4: System

The bits that make it actually useful.

- [ ] **ECALL/EBREAK**: System call interface
- [ ] **CSR instructions**: Control and status registers (basic set)
- [ ] **Fence instructions**: Memory ordering (likely NOPs on x86)

Status: **Not started.**

---

## Phase 5: ELF Loader

Load actual RISC-V binaries instead of hand-coded test cases.

- [ ] **ELF64 parser**: Read RISC-V executables
- [ ] **Section loading**: Map .text, .data, .rodata, .bss
- [ ] **Symbol resolution**: For debugging output
- [ ] **Entry point detection**: Find where to start

Status: **Not started.** Will require a stiff drink.

---

## Phase 6: Optimisation

Make it fast. Or at least faster.

- [ ] **Block caching**: Don't re-translate the same code
- [ ] **Hot path detection**: Identify frequently-executed blocks
- [ ] **Register allocation**: Map hot RISC-V regs to x86 regs
- [ ] **Peephole optimisation**: Combine common instruction sequences

Status: **Not started.** Premature optimisation is the root of all evil, but we'll get here eventually.

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

- [ ] **M extension**: Multiply/divide instructions
- [ ] **A extension**: Atomic operations
- [ ] **F/D extensions**: Floating-point (single/double)
- [ ] **C extension**: Compressed instructions
- [ ] **Linux syscall compatibility**: Run actual Linux RISC-V binaries
- [ ] **Self-hosting**: Translate a RISC-V build of Conway itself

---

## Philosophy

1. **Correctness first.** A slow correct answer beats a fast wrong one.
2. **Test everything.** If it's not tested, it's broken.
3. **Keep it simple.** Clever code is hard to debug.
4. **Document as you go.** Future you will thank present you.
5. **Have fun.** This is a hobby project, not a job.

---

*Last updated after Phase 2 completion. Kettle's on.*
