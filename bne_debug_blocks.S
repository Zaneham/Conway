# Force multiple blocks by using unconditional jumps
.section .text
.global _start

_start:
    j       test_bne        # Block 1: just a jump
test_bne:                   # Block 2: the problematic BNE
    bne     x0, x0, fail
    li      a0, 0
    li      a7, 93
    ecall
fail:
    li      a0, 1
    li      a7, 93
    ecall
