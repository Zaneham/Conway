# BNE preceded by li a0, 10
.section .text
.global _start

_start:
    li      a0, 10          # Same as branch_test_simple
    bne     x0, x0, fail    # Should NOT branch
    li      a0, 0           # PASS - overwrite a0
    li      a7, 93
    ecall

fail:
    li      a0, 1           # FAIL
    li      a7, 93
    ecall
