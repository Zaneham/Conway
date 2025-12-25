# Standalone Shift Tests for Conway
# Tests: SLL, SRL, SRA, SLLI, SRLI, SRAI

.section .text
.global _start

_start:
    # ============ SLL (Shift Left Logical) ============
    li      a0, 1
    li      a1, 4
    sll     a2, a0, a1          # a2 = 1 << 4 = 16
    li      t0, 16
    bne     a2, t0, fail

    li      a0, 0xFF
    li      a1, 8
    sll     a2, a0, a1          # a2 = 0xFF00
    li      t0, 0xFF00
    bne     a2, t0, fail

    # ============ SRL (Shift Right Logical) ============
    li      a0, 256
    li      a1, 4
    srl     a2, a0, a1          # a2 = 256 >> 4 = 16
    li      t0, 16
    bne     a2, t0, fail

    # SRL zero-extends (for negative numbers)
    li      a0, -16             # 0xFFFFFFFFFFFFFFF0
    li      a1, 4
    srl     a2, a0, a1          # Should have leading zeros
    # Check high bit is 0
    srli    t1, a2, 63
    bne     t1, zero, fail

    # ============ SRA (Shift Right Arithmetic) ============
    li      a0, -16             # 0xFFFFFFFFFFFFFFF0
    li      a1, 2
    sra     a2, a0, a1          # a2 = -4 (sign extended)
    li      t0, -4
    bne     a2, t0, fail

    li      a0, 64
    li      a1, 2
    sra     a2, a0, a1          # a2 = 16 (positive stays positive)
    li      t0, 16
    bne     a2, t0, fail

    # ============ SLLI (immediate) ============
    li      a0, 1
    slli    a2, a0, 10          # a2 = 1024
    li      t0, 1024
    bne     a2, t0, fail

    # ============ SRLI (immediate) ============
    li      a0, 1024
    srli    a2, a0, 5           # a2 = 32
    li      t0, 32
    bne     a2, t0, fail

    # ============ SRAI (immediate) ============
    li      a0, -128
    srai    a2, a0, 3           # a2 = -16
    li      t0, -16
    bne     a2, t0, fail

    # All tests passed
    li      a0, 0
    li      a7, 93
    ecall

fail:
    li      a0, 1
    li      a7, 93
    ecall
