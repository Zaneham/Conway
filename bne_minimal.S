# Minimal BNE test
.section .text
.global _start

_start:
    bne     x0, x0, fail    # should NOT branch
    li      a0, 0           # PASS - this should be executed
    j       exit
fail:
    li      a0, 1           # FAIL
exit:
    li      a7, 93
    ecall
