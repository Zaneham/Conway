# Simple test: is the bug about first block having ONLY a branch?
# Add one instruction before the branch
.section .text
.global _start

_start:
    addi    x0, x0, 0       # NOP at PC 0
    bne     x0, x0, fail    # PC 4, offset should be 16 to reach fail
    li      a0, 0           # PC 8
    li      a7, 93          # PC 12
    ecall                   # PC 16
fail:                       # PC 20
    li      a0, 1
    li      a7, 93
    ecall
