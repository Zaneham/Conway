# Test BNE with x0 - should NOT branch (0 != 0 is false)
.section .text
.global _start

_start:
    bne     x0, x0, fail    # Should NOT branch (0 == 0)
    li      a0, 0           # PASS
    li      a7, 93
    ecall

fail:
    li      a0, 1           # FAIL
    li      a7, 93
    ecall
