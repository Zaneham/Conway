# ld_neg_offset_test.S - Test LD with negative offset (like malloc uses)

.section .text
.global _start

_start:
    li sp, 0x6FFFF0

    # Set up a base address and store a known value
    li t0, 0x2000           # Base address
    li t1, 0xDEADBEEF12345678
    sd t1, 0(t0)            # Store at 0x2000

    # Now access it with a negative offset from a higher address
    li t2, 0x2100           # t2 = 0x2100
    ld t3, -256(t2)         # Load from 0x2100 - 0x100 = 0x2000

    # Verify t3 == t1
    bne t3, t1, fail1

    # Test with larger negative offset (-1912 like malloc)
    li t0, 0x3000           # Store at 0x3000
    li t1, 0xCAFEBABE87654321
    sd t1, 0(t0)

    li t2, 0x3778           # t2 = 0x3778 (0x3000 + 0x778)
    ld t3, -1912(t2)        # Load from 0x3778 - 1912 = 0x3000

    # Verify t3 == t1
    bne t3, t1, fail2

    # Success
    li a0, 0
    li a7, 93
    ecall

fail1:
    li a0, 91
    li a7, 93
    ecall

fail2:
    li a0, 92
    li a7, 93
    ecall
