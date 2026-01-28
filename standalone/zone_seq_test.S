# zone_seq_test.S - Test the specific sequence from I_ZoneBase
# Mimics: lui -> sw -> jal malloc -> mv s1,a0 -> lw a2 -> mv a1,a0 -> check

.section .text
.global _start

_start:
    li sp, 0x6FFFF0

    # Set up s2 to point to a memory location (like size_ptr)
    li s2, 0x2000

    # lui a0, 0x600 (size for "malloc")
    lui a0, 0x600

    # lui a5, 0x600; sw a5, 0(s2) - store size
    lui a5, 0x600
    sw a5, 0(s2)

    # Call fake malloc - just returns a known value
    jal ra, fake_malloc

    # mv s1, a0 - save malloc result (C.MV instruction)
    mv s1, a0

    # beqz a0, error - skip if NULL (shouldn't happen)
    beqz a0, fail_null

    # lw a2, 0(s2) - load size into a2
    lw a2, 0(s2)

    # mv a1, a0 - copy malloc result to a1 (C.MV instruction)
    mv a1, a0

    # Now verify: a1 should be 0x12345678, a2 should be 0x600000
    # Check a1
    li t0, 0x12345678
    bne a1, t0, fail_a1

    # Check a2 (shift right 20, should be 6)
    srli a0, a2, 20
    li t0, 6
    bne a0, t0, fail_a2

    # Success - exit 0
    li a0, 0
    li a7, 93
    ecall

fake_malloc:
    # Return a known value
    li a0, 0x12345678
    ret

fail_null:
    li a0, 88
    li a7, 93
    ecall

fail_a1:
    li a0, 91
    li a7, 93
    ecall

fail_a2:
    li a0, 92
    li a7, 93
    ecall
