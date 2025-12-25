# Standalone M Extension Tests for Conway
# Tests: MUL, MULH, MULHU, MULHSU, DIV, DIVU, REM, REMU

.section .text
.global _start

_start:
    # ============ MUL Tests ============
    li      a0, 7
    li      a1, 6
    mul     a2, a0, a1          # a2 = 42
    li      t0, 42
    bne     a2, t0, fail

    li      a0, -7
    li      a1, 6
    mul     a2, a0, a1          # a2 = -42
    li      t0, -42
    bne     a2, t0, fail

    li      a0, -7
    li      a1, -6
    mul     a2, a0, a1          # a2 = 42
    li      t0, 42
    bne     a2, t0, fail

    # ============ MULH Tests (signed high bits) ============
    li      a0, 0x7FFFFFFF      # Large positive
    li      a1, 2
    mulh    a2, a0, a1          # High bits of product
    li      t0, 0               # Should be 0 (product fits in 64 bits with high = 0)
    bne     a2, t0, fail

    # ============ DIV Tests ============
    li      a0, 42
    li      a1, 7
    div     a2, a0, a1          # a2 = 6
    li      t0, 6
    bne     a2, t0, fail

    li      a0, -42
    li      a1, 7
    div     a2, a0, a1          # a2 = -6
    li      t0, -6
    bne     a2, t0, fail

    li      a0, 42
    li      a1, -7
    div     a2, a0, a1          # a2 = -6
    li      t0, -6
    bne     a2, t0, fail

    li      a0, -42
    li      a1, -7
    div     a2, a0, a1          # a2 = 6
    li      t0, 6
    bne     a2, t0, fail

    # ============ DIVU Tests (unsigned) ============
    li      a0, 100
    li      a1, 10
    divu    a2, a0, a1          # a2 = 10
    li      t0, 10
    bne     a2, t0, fail

    # ============ REM Tests (signed remainder) ============
    li      a0, 47
    li      a1, 7
    rem     a2, a0, a1          # a2 = 5 (47 % 7 = 5)
    li      t0, 5
    bne     a2, t0, fail

    li      a0, -47
    li      a1, 7
    rem     a2, a0, a1          # a2 = -5
    li      t0, -5
    bne     a2, t0, fail

    # ============ REMU Tests (unsigned remainder) ============
    li      a0, 47
    li      a1, 7
    remu    a2, a0, a1          # a2 = 5
    li      t0, 5
    bne     a2, t0, fail

    # ============ Division by zero (returns -1 for div, dividend for rem) ============
    li      a0, 42
    li      a1, 0
    div     a2, a0, a1          # a2 = -1 (all bits set)
    li      t0, -1
    bne     a2, t0, fail

    li      a0, 42
    li      a1, 0
    rem     a2, a0, a1          # a2 = 42 (dividend)
    li      t0, 42
    bne     a2, t0, fail

    # All tests passed
    li      a0, 0
    li      a7, 93
    ecall

fail:
    li      a0, 1
    li      a7, 93
    ecall
