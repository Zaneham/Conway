# Debug the overflow test
# This traces the exact operations from add_test's overflow case

.section .text
.global _start

_start:
    # Step 1: addiw a0, zero, -1
    # Expected: a0 = 0xFFFFFFFFFFFFFFFF
    addiw   a0, zero, -1
    li      t0, -1
    bne     a0, t0, fail1

    # Step 2: slli a0, a0, 0x3f (shift left 63)
    # Expected: a0 = 0x8000000000000000
    slli    a0, a0, 63
    li      t0, 1
    slli    t0, t0, 63
    bne     a0, t0, fail2

    # Step 3: addi a0, a0, -1
    # Expected: a0 = 0x7FFFFFFFFFFFFFFF
    addi    a0, a0, -1
    li      t0, 1
    slli    t0, t0, 63
    addi    t0, t0, -1
    bne     a0, t0, fail3

    # All intermediate steps pass
    li      a0, 0
    li      a7, 93
    ecall

fail1:
    li      a0, 1
    li      a7, 93
    ecall

fail2:
    li      a0, 2
    li      a7, 93
    ecall

fail3:
    li      a0, 3
    li      a7, 93
    ecall
