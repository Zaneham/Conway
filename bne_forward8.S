# BNE forward with offset 8
.section .text
.global _start

_start:
    bne     x0, x0, fail    # offset 8 (next instruction is at +4, fail at +8)
    li      a0, 0           # PASS (should reach here)
fail:
    li      a7, 93          # Sets a7 to 93 - harmless if we fall through
    ecall
