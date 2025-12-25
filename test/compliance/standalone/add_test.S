# Standalone ADD instruction test for Conway
# Tests various edge cases for the ADD instruction

.section .text
.global _start

_start:
    # Test 1: Basic addition
    li      a0, 10
    li      a1, 20
    add     a2, a0, a1          # a2 = 30
    li      t0, 30
    bne     a2, t0, fail

    # Test 2: Add with zero
    li      a0, 42
    add     a2, a0, zero        # a2 = 42
    li      t0, 42
    bne     a2, t0, fail

    # Test 3: Add negative numbers
    li      a0, -10
    li      a1, -5
    add     a2, a0, a1          # a2 = -15
    li      t0, -15
    bne     a2, t0, fail

    # Test 4: Add positive and negative
    li      a0, 100
    li      a1, -30
    add     a2, a0, a1          # a2 = 70
    li      t0, 70
    bne     a2, t0, fail

    # Test 5: Overflow (wraps around)
    li      a0, 0x7FFFFFFFFFFFFFFF  # Max positive 64-bit
    li      a1, 1
    add     a2, a0, a1              # Wraps to negative
    li      t0, 0x8000000000000000  # Min negative
    bne     a2, t0, fail

    # Test 6: Same register as source and dest
    li      a0, 25
    li      a1, 17
    add     a0, a0, a1          # a0 = 42
    li      t0, 42
    bne     a0, t0, fail

    # Test 7: Both sources same register
    li      a0, 21
    add     a2, a0, a0          # a2 = 42
    li      t0, 42
    bne     a2, t0, fail

    # All tests passed - exit with code 0
    li      a0, 0
    li      a7, 93
    ecall

fail:
    # Test failed - exit with code 1
    li      a0, 1
    li      a7, 93
    ecall
