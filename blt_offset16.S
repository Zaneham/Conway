# BLT test - 0 < 0 is false, should NOT branch
.section .text
.global _start

_start:
    blt     x0, x0, fail    # 0 < 0 is false, offset 16
    li      a0, 0           # PASS
    li      a7, 93
    ecall
fail:
    li      a0, 1           # FAIL
    li      a7, 93
    ecall
