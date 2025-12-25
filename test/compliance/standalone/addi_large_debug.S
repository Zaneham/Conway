# Debug ADDI with large negative number

.section .text
.global _start

_start:
    # Start with 0x8000000000000000 (min negative)
    li      t0, 1
    slli    a0, t0, 63          # a0 = 0x8000000000000000

    # Exit with high bits of a0 to see if it's set correctly
    srli    a0, a0, 60          # Get high nibble (should be 8)
    li      a7, 93
    ecall
