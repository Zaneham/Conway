# BNE at PC 0 with offset exactly 16
.section .text
.global _start

_start:
    bne     x0, x0, target  # PC 0, should jump to PC+16 if taken
    li      a0, 0           # PC 4
    li      a7, 93          # PC 8
    ecall                   # PC 12
target:                     # PC 16
    li      a0, 1
    li      a7, 93
    ecall
