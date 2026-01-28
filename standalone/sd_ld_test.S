# sd_ld_test.S - Test SD/LD for 64-bit values

.section .text
.global _start

_start:
    li sp, 0x6FFF0
    li gp, 0x50000       # Simple GP value

    # Store a 64-bit value to memory
    li t0, 0xDEADBEEF    # Load the test value
    sd t0, 0(gp)         # Store at gp+0

    # Load it back
    ld t1, 0(gp)

    # Exit with upper byte of result as exit code
    # If value is 0x00000000DEADBEEF, t1>>56 = 0
    # If value is 0xFFFFFFFFDEADBEEF (wrong), t1>>56 = 0xFF
    srli a0, t1, 56
    li a7, 93
    ecall

.section .rodata
