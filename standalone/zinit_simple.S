# zinit_simple.S - Simplified Z_Init/I_ZoneBase test

.section .text
.global _start

_start:
    li sp, 0xFFF0
    li gp, 0x8000

    # Initialize heap_ptr at gp-1912
    li t0, 0x9568
    sd t0, -1912(gp)

    # Simulate Z_Init stack setup
    addi sp, sp, -32
    addi a0, sp, 12         # size_ptr on stack

    # Save return address
    sd ra, 24(sp)

    # Call I_ZoneBase logic inline
    mv s2, a0               # s2 = size_ptr

    # Store size to stack (like sw a5, 0(s2))
    lui a5, 0x600           # 0x600000
    sw a5, 0(s2)

    # Call malloc (inline)
    lui a0, 0x600
    ld a4, -1912(gp)
    addi a0, a0, 15
    andi a0, a0, -16
    add a0, a0, a4
    sd a0, -1912(gp)
    mv a0, a4               # return old heap_ptr

    # Now a0 = malloc result = 0x9568
    mv s1, a0               # save to s1

    beqz a0, fail_null

    # Load size from stack
    lw a2, 0(s2)            # Should be 0x600000

    # Copy malloc result to a1
    mv a1, a0               # Should be 0x9568

    # Verify a1
    li t0, 0x9568
    bne a1, t0, fail_a1

    # Verify a2
    lui t0, 0x600
    bne a2, t0, fail_a2

    # Success
    li a0, 0
    li a7, 93
    ecall

fail_null:
    li a0, 88
    li a7, 93
    ecall

fail_a1:
    mv a0, a1
    li a7, 93
    ecall

fail_a2:
    srli a0, a2, 20
    addi a0, a0, 100
    li a7, 93
    ecall
