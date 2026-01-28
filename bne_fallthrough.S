# BNE with fall-through to ecall
.section .text
.global _start

_start:
    bne     x0, x0, fail    # should NOT branch - offset 16
    li      a0, 0           # PASS
    li      a7, 93
    j       done            # skip fail
    nop
fail:                       # at offset 16
    li      a0, 1           # FAIL
    li      a7, 93
done:
    ecall
