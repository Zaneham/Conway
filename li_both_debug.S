# Test LI to both t1 and t2

.section .text
.global _start

_start:
    li      t1, 42
    li      t2, 100
    add     a0, t1, t2      # Should be 142
    li      a7, 93
    ecall
