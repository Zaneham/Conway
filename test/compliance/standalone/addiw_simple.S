# Simplest ADDIW test

.section .text
.global _start

_start:
    # Just do addiw and exit with the result
    addiw   a0, zero, 42        # a0 should be 42
    li      a7, 93
    ecall
