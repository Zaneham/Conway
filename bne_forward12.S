# BNE forward with offset 12
.section .text
.global _start

_start:
    bne     x0, x0, fail    # should NOT branch
    li      a0, 0           # PASS
    li      a7, 93
    ecall                   # at offset 12
fail:
    li      a0, 1           # FAIL
    li      a7, 93
    ecall
