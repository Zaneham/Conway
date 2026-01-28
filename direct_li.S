# Direct load to a0 - no MV
.section .text
.global _start

_start:
    li      a0, 42
    li      a7, 93
    ecall
