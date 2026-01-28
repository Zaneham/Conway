# BNE forward with proper offset 8 test
.section .text
.global _start

_start:
    bne     x0, x0, fail    # should NOT branch
    j       pass            # jump to pass
fail:
    li      a0, 1           # FAIL
    li      a7, 93
    ecall
pass:
    li      a0, 0           # PASS
    li      a7, 93
    ecall
