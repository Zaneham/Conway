# syscall_chain_test.S - Test syscall in the middle of I_ZoneBase logic
# This simulates what Doom does: syscalls before I_ZoneBase

.section .text
.global _start

_start:
    li sp, 0xFFF0
    li gp, 0x8000

    # Initialize heap_ptr
    li t0, 0x9568
    sd t0, -1912(gp)

    # Do a write syscall (like Doom's startup messages)
    li a7, 64               # write syscall
    li a0, 1                # stdout
    la a1, msg             # buffer
    li a2, 4                # length
    ecall

    # Now call the zone test
    jal ra, Z_Init

    li a7, 93
    ecall

.section .rodata
msg: .ascii "TST\n"

.section .text
Z_Init:
    addi sp, sp, -32
    sd ra, 0(sp)
    addi a0, sp, 12
    jal ra, I_ZoneBase
    li t0, 0x9568
    beq a0, t0, Z_success
    ld ra, 0(sp)
    addi sp, sp, 32
    ret
Z_success:
    li a0, 0
    ld ra, 0(sp)
    addi sp, sp, 32
    ret

I_ZoneBase:
    addi sp, sp, -32
    sd s2, 0(sp)
    mv s2, a0
    li a1, 1                # Will be overwritten
    sd ra, 24(sp)
    sd s0, 16(sp)
    sd s1, 8(sp)

    # Do another syscall in the middle!
    li a7, 64
    li a0, 1
    la a1, msg2
    li a2, 4
    ecall

    # Continue with I_ZoneBase logic
    lui a0, 0x600
    lui a5, 0x600
    li s0, 6
    sw a5, 0(s2)

    jal ra, fake_malloc

    mv s1, a0
    beqz a0, fail_null

    lw a2, 0(s2)
    mv a1, a0

    li t0, 0x9568
    bne a1, t0, fail_a1

    lui t0, 0x600
    bne a2, t0, fail_a2

    mv a0, s1
    j done

fail_null:
    li a0, 88
    j done

fail_a1:
    mv a0, a1
    j done

fail_a2:
    srli a0, a2, 20
    addi a0, a0, 100
    j done

done:
    ld ra, 24(sp)
    ld s0, 16(sp)
    ld s1, 8(sp)
    ld s2, 0(sp)
    addi sp, sp, 32
    ret

fake_malloc:
    ld a4, -1912(gp)
    addi a0, a0, 15
    andi a0, a0, -16
    add a0, a0, a4
    sd a0, -1912(gp)
    mv a0, a4
    ret

.section .rodata
msg2: .ascii "ZN\n\0"
