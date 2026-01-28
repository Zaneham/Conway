# BNE with offset 14 (should work)
.section .text
.global _start

_start:
    bne     x0, x0, fail    # offset 14
    li      a0, 0           # PASS
    li      a7, 93
    .hword  0               # 2 bytes padding
fail:                       # at offset 14
    li      a0, 1
    li      a7, 93
    ecall
