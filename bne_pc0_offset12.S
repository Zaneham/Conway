# BNE at PC 0 with offset 12
.section .text
.global _start

_start:
    bne     x0, x0, target  # PC 0, offset 12
    li      a0, 0           # PC 4
    li      a7, 93          # PC 8
target:                     # PC 12
    ecall                   # PC 12 - both paths end here
# If not taken: a0=0, if taken: a0=undefined (0 from init)
