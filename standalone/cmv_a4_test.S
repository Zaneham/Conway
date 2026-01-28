# cmv_a4_test.S - Test C.MV a0, a4 (the exact instruction in malloc return)
# Encoding: 853a = C.MV a0, a4

.section .text
.global _start

_start:
    li sp, 0xFFF0

    # Load a known value into a4
    li a4, 0x9568

    # Clear a0
    li a0, 0

    # Execute C.MV a0, a4 (should copy 0x9568 to a0)
    # The assembler should generate: 853a
    mv a0, a4

    # Check result
    li t0, 0x9568
    beq a0, t0, success

    # Failed - return what a0 actually is
    li a7, 93
    ecall

success:
    li a0, 0
    li a7, 93
    ecall
