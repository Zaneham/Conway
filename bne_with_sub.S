# Test with SUB to set flags differently before BNE
.section .text
.global _start

_start:
    li      t0, 5
    li      t1, 5
    sub     t2, t0, t1      # t2 = 5 - 5 = 0, sets ZF=1 (in x86)
    bne     x0, x0, fail    # Should NOT branch, offset 16
    li      a0, 0           # PASS
    li      a7, 93
    ecall
fail:
    li      a0, 1
    li      a7, 93
    ecall
