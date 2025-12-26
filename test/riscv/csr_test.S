# csr_test.S - Test CSR instructions
# Tests csrr (read-only CSR operations)

.section .text
.global _start

_start:
    # Test 1: Read misa register
    # misa should return 0x8000000000001104 for RV64IMC
    # We'll just check that it's non-zero
    csrr    a0, misa            # Read misa into a0
    beqz    a0, fail1           # If zero, fail

    # Test 2: Read cycle counter
    # Should return a non-zero value (from RDTSC)
    csrr    a1, cycle           # Read cycle into a1
    beqz    a1, fail2           # If zero (unlikely), fail

    # Test 3: Check misa has the right bits set
    # Bit 2 (C extension) should be set
    li      t0, 4               # 1 << 2
    and     t1, a0, t0
    beqz    t1, fail3           # C bit not set

    # Bit 8 (I base) should be set
    li      t0, 256             # 1 << 8
    and     t1, a0, t0
    beqz    t1, fail4           # I bit not set

    # Bit 12 (M extension) should be set
    li      t0, 4096            # 1 << 12
    and     t1, a0, t0
    beqz    t1, fail5           # M bit not set

    # All tests passed - exit with 0
    li      a0, 0
    j       exit

fail1:
    li      a0, 1
    j       exit
fail2:
    li      a0, 2
    j       exit
fail3:
    li      a0, 3
    j       exit
fail4:
    li      a0, 4
    j       exit
fail5:
    li      a0, 5
    j       exit

exit:
    li      a7, 93              # exit syscall
    ecall

spin:
    j       spin
