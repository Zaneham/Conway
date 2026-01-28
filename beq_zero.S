# Test BEQ with x0 - should always NOT branch (0 == 0 is true)
.section .text
.global _start

_start:
    beq     x0, x0, pass    # Should branch (0 == 0)
    li      a0, 1           # FAIL - shouldn't reach here
    li      a7, 93
    ecall

pass:
    li      a0, 0           # PASS
    li      a7, 93
    ecall
