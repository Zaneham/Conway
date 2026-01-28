# Check the value of x0 before branching
.section .text
.global _start

_start:
    # First, verify x0 is 0 by moving it to a0
    add     a0, x0, x0      # a0 = x0 + x0 = 0 + 0 = 0
    # Now do the problematic branch
    bne     x0, x0, fail    # offset 16
    addi    a0, a0, 10      # Should execute: a0 = 10
    li      a7, 93
    ecall
fail:
    li      a0, 99
    li      a7, 93
    ecall
# Expected: 10 (not taken), Actual: 99 if branch taken, 0 if x0 check fails
