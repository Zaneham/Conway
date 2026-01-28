# BNE with offset 12 (matching branch_test_simple)
.section .text
.global _start

_start:
    li      a0, 10
    bne     x0, x0, fail    # Target should be at +12
    li      a0, 0
    j       done            # Jump over fail to match structure
fail:
    li      a0, 1
done:
    li      a7, 93
    ecall
