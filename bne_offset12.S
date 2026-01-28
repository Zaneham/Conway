# BNE with offset 12 (not 16)
.section .text
.global _start

_start:
    bne     x0, x0, fail    # Should NOT branch
    nop                     # Force different offset
    li      a0, 0           # PASS
    li      a7, 93
    ecall

fail:
    li      a0, 1           # FAIL
    li      a7, 93
    ecall
