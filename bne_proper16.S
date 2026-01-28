# BNE forward with proper offset 16 test
.section .text
.global _start

_start:
    bne     x0, x0, fail    # should NOT branch - offset 16
    j       pass            # if not taken, jump to pass
    nop                     # padding
    nop                     # more padding to make offset 16
fail:                       # at offset 16
    li      a0, 1           # FAIL
    li      a7, 93
    ecall
pass:
    li      a0, 0           # PASS
    li      a7, 93
    ecall
