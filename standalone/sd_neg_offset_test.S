# sd_neg_offset_test.S - Test SD/LD with negative offset

.section .text
.global _start

_start:
    li sp, 0x6FFF0
    li gp, 0x57608       # GP value like in gp_trace_test

    # Store a 64-bit value to memory at gp-1912 (like gp_trace_test)
    li t0, 0xDEADBEEF
    sd t0, -1912(gp)     # Store at gp-0x778 = 0x56E90

    # Load it back
    ld t1, -1912(gp)

    # Exit with upper byte of result as exit code
    srli a0, t1, 56
    li a7, 93
    ecall

.section .rodata
