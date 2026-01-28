# BEQ at PC 0 with offset 16 - should TAKE the branch
.section .text
.global _start

_start:
    beq     x0, x0, target  # PC 0, should branch to PC 16
    li      a0, 1           # PC 4 - FAIL (should skip)
    li      a7, 93          # PC 8
    ecall                   # PC 12
target:                     # PC 16
    li      a0, 0           # PASS
    li      a7, 93
    ecall
