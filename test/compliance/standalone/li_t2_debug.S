# Debug LI to t2

.section .text
.global _start

_start:
    li      t2, 42
    mv      a0, t2
    li      a7, 93
    ecall
