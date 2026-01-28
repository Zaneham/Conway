# Test x0 by adding it to itself
.section .text
.global _start

_start:
    add     a0, x0, x0  # a0 = x0 + x0 = 0 + 0 = 0
    li      a7, 93
    ecall
# Expected: exit(0)
