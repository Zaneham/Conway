# Debug BNE comparison

.section .text
.global _start

_start:
    # Simple test: are 127 and 127 equal?
    li      t1, 127
    li      t2, 127
    bne     t1, t2, fail

    # Pass
    li      a0, 0
    li      a7, 93
    ecall

fail:
    li      a0, 1
    li      a7, 93
    ecall
