# BNE x0, x0 backward - should NOT branch
.section .text
.global _start

_start:
    j       test
fail:
    li      a0, 1           # FAIL
    li      a7, 93
    ecall
test:
    bne     x0, x0, fail    # 0 == 0, should NOT branch (backward)
    li      a0, 0           # PASS
    li      a7, 93
    ecall
