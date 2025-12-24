# mul_test.S - Test M extension (multiply/divide)
# "Multiplication: making numbers bigger since forever"

.section .text
.global _start

_start:
    # Test MUL: 7 * 8 = 56
    li      a0, 7
    li      a1, 8
    mul     a0, a0, a1      # a0 = 7 * 8 = 56

    # Test DIV: 56 / 7 = 8
    li      a1, 7
    div     a2, a0, a1      # a2 = 56 / 7 = 8

    # Test REM: 57 % 7 = 1
    li      a0, 57
    li      a1, 7
    rem     a3, a0, a1      # a3 = 57 % 7 = 1

    # Result = 8 + 1 = 9 (div result + rem result)
    add     a0, a2, a3      # a0 = 8 + 1 = 9

    # Exit with result
    li      a7, 93
    ecall
