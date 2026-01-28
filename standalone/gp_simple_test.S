# gp_simple_test.S - Test GP with LI (no AUIPC)

.section .text
.global _start

_start:
    # Initialize SP
    li sp, 0x6FFF0

    # Set GP directly with LI (not AUIPC)
    li gp, 0x12345678

    # Print GP:
    li a7, 64
    li a0, 1
    la a1, msg_gp
    li a2, 3
    ecall

    mv a0, gp
    jal ra, print_hex8

    li a7, 64
    li a0, 1
    la a1, newline
    li a2, 1
    ecall

    # Verify GP value
    li t0, 0x12345678
    bne gp, t0, fail

    # Success
    li a7, 64
    li a0, 1
    la a1, msg_pass
    li a2, 5
    ecall

    li a0, 0
    li a7, 93
    ecall

fail:
    li a7, 64
    li a0, 1
    la a1, msg_fail
    li a2, 5
    ecall

    li a0, 1
    li a7, 93
    ecall

# print_hex8(a0)
print_hex8:
    addi sp, sp, -32
    sd ra, 24(sp)
    sd s0, 16(sp)
    sd s1, 8(sp)

    mv s0, a0
    li s1, 8
    addi a0, sp, 0

.ph_loop:
    srli t0, s0, 28
    andi t0, t0, 0xF
    li t1, 10
    blt t0, t1, .ph_digit
    addi t0, t0, 'A' - 10
    j .ph_store
.ph_digit:
    addi t0, t0, '0'
.ph_store:
    sb t0, 0(a0)
    addi a0, a0, 1
    slli s0, s0, 4
    addi s1, s1, -1
    bnez s1, .ph_loop

    li a7, 64
    li a0, 1
    addi a1, sp, 0
    li a2, 8
    ecall

    ld ra, 24(sp)
    ld s0, 16(sp)
    ld s1, 8(sp)
    addi sp, sp, 32
    ret

.section .rodata
msg_gp:     .ascii "GP:"
msg_pass:   .ascii "PASS\n"
msg_fail:   .ascii "FAIL\n"
newline:    .ascii "\n"
