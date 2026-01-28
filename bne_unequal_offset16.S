# BNE that SHOULD take the branch (unequal values, offset 16)
.section .text
.global _start

_start:
    li      t0, 1
    bne     t0, x0, pass    # 1 != 0, should branch
    li      a0, 1           # FAIL
    li      a7, 93
    ecall
pass:
    li      a0, 0           # PASS
    li      a7, 93
    ecall
