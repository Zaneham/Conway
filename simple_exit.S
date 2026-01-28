# Simple exit test - should return 42
.section .text
.global _start

_start:
    li      a0, 42          # exit code
    li      a7, 93          # ecall number
    ecall
