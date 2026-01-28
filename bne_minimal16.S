# Minimal BNE test with offset 16
.section .text
.global _start

_start:
    bne     x0, x0, fail    # should NOT branch - target offset 16
    li      a0, 0           # PASS
    j       exit            # jump to exit
    nop                     # padding to make offset 16
fail:
    li      a0, 1           # FAIL
exit:
    li      a7, 93
    ecall
