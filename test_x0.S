# Test if x0 is 0
.section .text
.global _start

_start:
    mv      a0, x0      # Copy x0 to a0
    li      a7, 93
    ecall
# Expected: exit(0)
