# Standalone Arithmetic Tests for Conway
# Tests: ADD, SUB, AND, OR, XOR, SLT, SLTU

.section .text
.global _start

_start:
    # ============ ADD Tests ============
    li      a0, 10
    li      a1, 20
    add     a2, a0, a1          # a2 = 30
    li      t0, 30
    bne     a2, t0, fail

    # ============ SUB Tests ============
    li      a0, 50
    li      a1, 30
    sub     a2, a0, a1          # a2 = 20
    li      t0, 20
    bne     a2, t0, fail

    li      a0, 10
    li      a1, 30
    sub     a2, a0, a1          # a2 = -20
    li      t0, -20
    bne     a2, t0, fail

    # ============ AND Tests ============
    li      a0, 0xFF00FF00
    li      a1, 0x0F0F0F0F
    and     a2, a0, a1          # a2 = 0x0F000F00
    li      t0, 0x0F000F00
    bne     a2, t0, fail

    # ============ OR Tests ============
    li      a0, 0xFF00FF00
    li      a1, 0x00FF00FF
    or      a2, a0, a1          # a2 = 0xFFFFFFFF
    li      t0, 0xFFFFFFFF
    bne     a2, t0, fail

    # ============ XOR Tests ============
    li      a0, 0xFF00FF00
    li      a1, 0xFFFF0000
    xor     a2, a0, a1          # a2 = 0x00FFFF00
    li      t0, 0x00FFFF00
    bne     a2, t0, fail

    # ============ SLT Tests (signed less than) ============
    li      a0, -5
    li      a1, 10
    slt     a2, a0, a1          # a2 = 1 (-5 < 10)
    li      t0, 1
    bne     a2, t0, fail

    li      a0, 10
    li      a1, -5
    slt     a2, a0, a1          # a2 = 0 (10 !< -5)
    li      t0, 0
    bne     a2, t0, fail

    # ============ SLTU Tests (unsigned less than) ============
    li      a0, 5
    li      a1, 10
    sltu    a2, a0, a1          # a2 = 1 (5 < 10)
    li      t0, 1
    bne     a2, t0, fail

    li      a0, -1              # This is 0xFFFFFFFFFFFFFFFF unsigned
    li      a1, 10
    sltu    a2, a0, a1          # a2 = 0 (max unsigned !< 10)
    li      t0, 0
    bne     a2, t0, fail

    # All tests passed
    li      a0, 0
    li      a7, 93
    ecall

fail:
    li      a0, 1
    li      a7, 93
    ecall
