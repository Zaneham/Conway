# BNE preceded by NOP
.section .text
.global _start

_start:
    nop                     # Add NOP before BNE
    bne     x0, x0, fail    # Should NOT branch
    li      a0, 0           # PASS
    li      a7, 93
    ecall

fail:
    li      a0, 1           # FAIL
    li      a7, 93
    ecall
