# BNE x0, x0 should NOT branch - return 0 (PASS)
.section .text
.global _start

_start:
    bne     x0, x0, fail    # 0 == 0, should NOT branch
    li      a0, 0           # PASS
    li      a7, 93
    ecall
fail:
    li      a0, 1           # FAIL
    li      a7, 93
    ecall
