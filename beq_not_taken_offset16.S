# BEQ that should NOT take the branch (testing not-taken path with offset 16)
.section .text
.global _start

_start:
    li      t0, 1           # t0 = 1
    beq     t0, x0, fail    # 1 != 0, should NOT branch (offset 16)
    li      a0, 0           # PASS
    li      a7, 93
    ecall
fail:
    li      a0, 1           # FAIL
    li      a7, 93
    ecall
