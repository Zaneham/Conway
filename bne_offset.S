# BNE at offset 4 (not at 0x1000)
.section .text
.global _start

_start:
    nop                     # 0x1000
    nop                     # 0x1004
    nop                     # 0x1008
    nop                     # 0x100C
    bne     x0, x0, fail    # 0x1010: Should NOT branch
    li      a0, 0           # PASS
    li      a7, 93
    ecall

fail:
    li      a0, 1           # FAIL
    li      a7, 93
    ecall
