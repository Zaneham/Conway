# BNE preceded by an instruction that modifies a register
.section .text
.global _start

_start:
    li      t0, 0           # Load 0 into t0 (does nothing useful)
    bne     x0, x0, fail    # Should NOT branch (0 == 0)
    li      a0, 0           # PASS
    li      a7, 93
    ecall

fail:
    li      a0, 1           # FAIL
    li      a7, 93
    ecall
