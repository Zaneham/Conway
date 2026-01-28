# Test BNE with various offsets
.section .text
.global _start

_start:
    li      a0, 100         # Will add offsets to this

    # Test offset 8
    bne     x0, x0, off8
    addi    a0, a0, 1       # a0 = 101 if not taken
off8:
    # Test offset 12
    bne     x0, x0, off12
    addi    a0, a0, 2       # a0 = 103 if not taken
off12:
    # Test offset 16
    bne     x0, x0, off16
    addi    a0, a0, 4       # a0 = 107 if not taken
    j       done
off16:
    addi    a0, a0, 8       # Wrong path
done:
    li      a7, 93
    ecall
# Expected: a0 = 100 + 1 + 2 + 4 = 107 if all BNE NOT taken
