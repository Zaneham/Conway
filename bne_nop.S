# BNE with nop after it
.section .text
.global _start

_start:
    bne     x0, x0, fail    # should NOT branch - offset 16
    nop                     # extra nop
    li      a0, 0           # PASS
    li      a7, 93
    ecall
fail:                       # at offset 16 (adjusted)
    li      a0, 1           # FAIL
    li      a7, 93
    ecall
