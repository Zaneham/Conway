# Print a character and exit
.section .text
.global _start

_start:
    li      a0, 65          # 'A'
    li      a1, 1           # stdout
    li      a2, 1           # length
    li      a7, 64          # write syscall
    ecall
    li      a0, 0
    li      a7, 93
    ecall
