# Debug ADDI with 0x8000...0 - 1

.section .text
.global _start

_start:
    # Create 0x8000000000000000
    li      t0, 1
    slli    a0, t0, 63          # a0 = 0x8000000000000000

    # Exit with high byte to verify a0 is correct
    srli    t1, a0, 56          # t1 = 0x80
    li      t2, 0x80
    bne     t1, t2, fail1

    # Now do ADDI a0, a0, -1
    addi    a0, a0, -1          # a0 = 0x7FFFFFFFFFFFFFFF

    # Check high byte should be 0x7F
    srli    t1, a0, 56
    li      t2, 0x7F
    bne     t1, t2, fail2

    # All OK
    li      a0, 0
    li      a7, 93
    ecall

fail1:
    mv      a0, t1              # Return actual high byte
    li      a7, 93
    ecall

fail2:
    addi    a0, t1, 100         # Return 100 + actual high byte
    li      a7, 93
    ecall
