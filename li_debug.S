# Debug LI to t1 and t2

.section .text
.global _start

_start:
    # Load 42 into t1 and exit with it
    li      t1, 42
    mv      a0, t1
    li      a7, 93
    ecall
