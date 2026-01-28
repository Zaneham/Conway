# BNE at PC 0 with offset 20
.section .text
.global _start

_start:
    bne     x0, x0, target  # PC 0
    li      a0, 0           # PC 4
    li      a7, 93          # PC 8
    nop                     # PC 12
    ecall                   # PC 16
target:                     # PC 20
    li      a0, 1
    li      a7, 93
    ecall
