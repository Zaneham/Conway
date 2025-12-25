# Standalone Immediate and Upper Tests for Conway
# Tests: ADDI, SLTI, SLTIU, XORI, ORI, ANDI, LUI, AUIPC

.section .text
.global _start

_start:
    # ============ ADDI Tests ============
    li      a0, 35
    addi    a1, a0, 7           # a1 = 42
    li      t0, 42
    bne     a1, t0, fail

    addi    a1, zero, 100       # a1 = 100
    li      t0, 100
    bne     a1, t0, fail

    li      a0, 50
    addi    a1, a0, -8          # a1 = 42
    li      t0, 42
    bne     a1, t0, fail

    # ============ SLTI Tests (signed compare immediate) ============
    li      a0, 5
    slti    a1, a0, 10          # a1 = 1 (5 < 10)
    li      t0, 1
    bne     a1, t0, fail

    li      a0, 15
    slti    a1, a0, 10          # a1 = 0 (15 !< 10)
    li      t0, 0
    bne     a1, t0, fail

    li      a0, -10
    slti    a1, a0, 5           # a1 = 1 (-10 < 5)
    li      t0, 1
    bne     a1, t0, fail

    # ============ SLTIU Tests (unsigned compare immediate) ============
    li      a0, 5
    sltiu   a1, a0, 10          # a1 = 1
    li      t0, 1
    bne     a1, t0, fail

    li      a0, -1              # Max unsigned
    sltiu   a1, a0, 10          # a1 = 0 (max !< 10)
    li      t0, 0
    bne     a1, t0, fail

    # ============ XORI Tests ============
    li      a0, 0xFF
    xori    a1, a0, 0x0F        # a1 = 0xF0
    li      t0, 0xF0
    bne     a1, t0, fail

    li      a0, 0xFF
    xori    a1, a0, -1          # a1 = ~0xFF = NOT operation
    # Check result is inverted
    and     t0, a0, a1          # Should be 0 if properly inverted
    bne     t0, zero, fail

    # ============ ORI Tests ============
    li      a0, 0xF0
    ori     a1, a0, 0x0F        # a1 = 0xFF
    li      t0, 0xFF
    bne     a1, t0, fail

    # ============ ANDI Tests ============
    li      a0, 0xFF
    andi    a1, a0, 0x0F        # a1 = 0x0F
    li      t0, 0x0F
    bne     a1, t0, fail

    # ============ LUI Tests ============
    lui     a0, 0x12345         # a0 = 0x12345000
    li      t0, 0x12345000
    bne     a0, t0, fail

    lui     a0, 0xFFFFF         # High bit set - sign extends
    srli    t0, a0, 44          # Check high bits
    li      t1, 0xFFFFF
    bne     t0, t1, fail

    # ============ AUIPC Tests ============
    auipc   a0, 0               # a0 = current PC
    # Just verify it's non-zero and in expected range
    beq     a0, zero, fail

    auipc   a0, 1               # a0 = PC + 0x1000
    auipc   a1, 0               # a1 = current PC (a bit later)
    sub     t0, a0, a1          # Difference should be close to 0x1000
    li      t1, 0x1000
    sub     t0, t0, t1          # Should be small (just the offset of instructions)
    li      t1, 0x100           # Allow some slack
    bge     t0, t1, fail        # If difference > 256, something wrong

    # All tests passed
    li      a0, 0
    li      a7, 93
    ecall

fail:
    li      a0, 1
    li      a7, 93
    ecall
