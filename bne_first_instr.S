# BNE as FIRST instruction - does it branch incorrectly?
.section .text
.global _start

_start:
    bne     x0, x0, fail    # First instruction - should NOT branch
    li      a0, 0           # PASS
    li      a7, 93
    ecall

fail:
    li      a0, 1           # FAIL
    li      a7, 93
    ecall
