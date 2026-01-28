# atomic_test.S - Test A extension (atomic operations)
# Tests LR/SC, AMOSWAP, AMOADD, AMOAND, AMOOR, AMOXOR, AMOMIN, AMOMAX

.section .data
.align 8
counter:    .dword 100              # Test value
swap_val:   .dword 0                # For swap test
min_val:    .dword 50               # For min/max tests
max_val:    .dword 150              # For min/max tests

.section .text
.global _start

_start:
    # Test 1: LR.D / SC.D (Load-Reserved / Store-Conditional)
    # This is the basic atomic pattern: load, modify, try store
    la      a0, counter

    li      t0, 0                   # Retry counter (should be 0 on first try)
.lr_sc_retry:
    lr.d    a1, (a0)                # a1 = load-reserved from counter
    addi    a2, a1, 1               # a2 = a1 + 1 = 101
    sc.d    a3, a2, (a0)            # try to store 101, a3 = 0 if success
    bnez    a3, .lr_sc_retry        # retry if failed

    # Verify counter is now 101
    ld      t0, 0(a0)
    li      t1, 101
    bne     t0, t1, fail_lr_sc

    # Test 2: AMOSWAP.D - Atomically swap values
    la      a0, swap_val
    li      t0, 42
    amoswap.d a1, t0, (a0)          # a1 = old value (0), [a0] = 42

    # a1 should be 0 (old value)
    bnez    a1, fail_swap

    # swap_val should now be 42
    ld      t0, 0(a0)
    li      t1, 42
    bne     t0, t1, fail_swap

    # Test 3: AMOADD.D - Atomically add
    la      a0, counter             # counter = 101 from earlier
    li      t0, 99
    amoadd.d a1, t0, (a0)           # a1 = old (101), [a0] = 101 + 99 = 200

    # a1 should be 101
    li      t1, 101
    bne     a1, t1, fail_add

    # counter should now be 200
    ld      t0, 0(a0)
    li      t1, 200
    bne     t0, t1, fail_add

    # Test 4: AMOAND.D - Atomically AND
    la      a0, counter             # counter = 200 = 0b11001000
    li      t0, 0xFF                # AND with 255
    amoand.d a1, t0, (a0)           # a1 = old (200), [a0] = 200 & 255 = 200 (no change since < 256)

    # a1 should be 200
    li      t1, 200
    bne     a1, t1, fail_and

    # counter should still be 200
    ld      t0, 0(a0)
    li      t1, 200
    bne     t0, t1, fail_and

    # Test 5: AMOOR.D - Atomically OR
    la      a0, counter             # counter = 200 = 0b11001000
    li      t0, 0x300               # OR with 768 = 0b1100000000
    amoor.d a1, t0, (a0)            # a1 = old (200), [a0] = 200 | 768 = 968

    # a1 should be 200
    li      t1, 200
    bne     a1, t1, fail_or

    # counter should be 968
    ld      t0, 0(a0)
    li      t1, 968
    bne     t0, t1, fail_or

    # Test 6: AMOXOR.D - Atomically XOR
    la      a0, counter             # counter = 968
    li      t0, 968                 # XOR with itself
    amoxor.d a1, t0, (a0)           # a1 = old (968), [a0] = 968 ^ 968 = 0

    # a1 should be 968
    li      t1, 968
    bne     a1, t1, fail_xor

    # counter should be 0
    ld      t0, 0(a0)
    bnez    t0, fail_xor

    # Test 7: AMOMIN.D - Atomically minimum (signed)
    la      a0, min_val             # min_val = 50
    li      t0, 75
    amomin.d a1, t0, (a0)           # a1 = old (50), [a0] = min(50, 75) = 50

    # a1 should be 50
    li      t1, 50
    bne     a1, t1, fail_min

    # min_val should still be 50 (since 50 < 75)
    ld      t0, 0(a0)
    li      t1, 50
    bne     t0, t1, fail_min

    # Test with smaller value
    li      t0, 25
    amomin.d a1, t0, (a0)           # a1 = old (50), [a0] = min(50, 25) = 25

    # a1 should be 50 (old value)
    li      t1, 50
    bne     a1, t1, fail_min

    # min_val should now be 25
    ld      t0, 0(a0)
    li      t1, 25
    bne     t0, t1, fail_min

    # Test 8: AMOMAX.D - Atomically maximum (signed)
    la      a0, max_val             # max_val = 150
    li      t0, 100
    amomax.d a1, t0, (a0)           # a1 = old (150), [a0] = max(150, 100) = 150

    # a1 should be 150
    li      t1, 150
    bne     a1, t1, fail_max

    # max_val should still be 150
    ld      t0, 0(a0)
    li      t1, 150
    bne     t0, t1, fail_max

    # Test with larger value
    li      t0, 200
    amomax.d a1, t0, (a0)           # a1 = old (150), [a0] = max(150, 200) = 200

    # a1 should be 150 (old value)
    li      t1, 150
    bne     a1, t1, fail_max

    # max_val should now be 200
    ld      t0, 0(a0)
    li      t1, 200
    bne     t0, t1, fail_max

    # All tests passed!
    li      a0, 0
    j       exit

fail_lr_sc:
    li      a0, 1
    j       exit

fail_swap:
    li      a0, 2
    j       exit

fail_add:
    li      a0, 3
    j       exit

fail_and:
    li      a0, 4
    j       exit

fail_or:
    li      a0, 5
    j       exit

fail_xor:
    li      a0, 6
    j       exit

fail_min:
    li      a0, 7
    j       exit

fail_max:
    li      a0, 8
    j       exit

exit:
    li      a7, 93                  # exit syscall
    ecall

spin:
    j       spin
