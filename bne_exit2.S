# BNE with different exit codes to check
.section .text
.global _start

_start:
    bne     x0, x0, target  # PC 0, offset 16
    li      a0, 42          # PC 4 - not taken path
    li      a7, 93          # PC 8
    ecall                   # PC 12
target:                     # PC 16
    li      a0, 99          # taken path
    li      a7, 93
    ecall
# Expected: 42 (not taken), Actual: 99 if bug exists
