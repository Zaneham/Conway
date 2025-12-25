# Debug test for ADDIW instruction
# addiw should do 32-bit add then sign-extend to 64 bits

.section .text
.global _start

_start:
    # Test 1: Simple addiw
    # 0x10000 - 256 = 0xFF00 (should be 0x000000000000FF00)
    lui     t0, 0x10            # t0 = 0x10000
    addiw   t0, t0, -256        # t0 = 0xFF00 (32-bit), sign-extend to 64-bit

    # Check if it's 0xFF00
    li      t1, 0xFF00
    beq     t0, t1, test2

    # Debug: exit with the actual value shifted right
    srli    a0, t0, 8           # Show high bits
    li      a7, 93
    ecall

test2:
    # Test 2: addiw with zero
    addiw   t0, zero, 42        # t0 = 42
    li      t1, 42
    beq     t0, t1, test3

    li      a0, 2
    li      a7, 93
    ecall

test3:
    # Test 3: addiw negative result
    addiw   t0, zero, -1        # t0 = -1 (should be 0xFFFFFFFFFFFFFFFF)
    li      t1, -1
    beq     t0, t1, pass

    li      a0, 3
    li      a7, 93
    ecall

pass:
    li      a0, 0
    li      a7, 93
    ecall
