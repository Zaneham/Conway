# BNE forward with proper offset 14 test
.section .text
.global _start

_start:
    bne     x0, x0, fail    # should NOT branch - offset 14
    j       pass            # if not taken, jump to pass
    nop                     # padding
    .hword  0               # 2 more bytes to make offset 14
fail:                       # at offset 14
    li      a0, 1           # FAIL
    li      a7, 93
    ecall
pass:
    li      a0, 0           # PASS
    li      a7, 93
    ecall
