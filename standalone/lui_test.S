# lui_test.S - Simple LUI test
# Expected exit code: 6 (from 0x600000 >> 20)

.section .text
.global _start

_start:
    # Test LUI with 0x600
    lui a0, 0x600           # a0 = 0x600000

    # Shift right 20 to get 6
    srli a0, a0, 20         # a0 = 6

    # Exit with a0
    li a7, 93
    ecall
