# doom_chain_test.S - Simulate Doom's initialization chain
# Uses AUIPC to set gp, then does function calls before I_ZoneBase

.section .text
.global _start

# Layout (matching Doom's pattern):
# gp will be set to PC + offset (via AUIPC)
# heap_ptr will be at gp-1912

_start:
    li sp, 0xFFF0

    # Set up gp using AUIPC like Doom does
    # We want gp = 0x8000, so imm = (0x8000 - PC) >> 12 adjusted for AUIPC
    # For simplicity, just use li (the actual Doom uses AUIPC+ADDI)
    li gp, 0x8000

    # Initialize heap_ptr at gp-1912
    li t0, 0x9568
    sd t0, -1912(gp)

    # Simulate the call chain: _start -> main -> doomgeneric_Create -> Z_Init
    jal ra, main

    li a7, 93
    ecall

main:
    addi sp, sp, -16
    sd ra, 0(sp)

    # Call doomgeneric_Create (simulated)
    jal ra, doom_create

    ld ra, 0(sp)
    addi sp, sp, 16
    ret

doom_create:
    addi sp, sp, -16
    sd ra, 0(sp)

    # Do some operations that might affect registers
    li a0, 0
    li a1, 0
    li a2, 0
    li a3, 0
    li a4, 0
    li a5, 0

    # Call Z_Init
    jal ra, Z_Init

    # Return result from Z_Init
    ld ra, 0(sp)
    addi sp, sp, 16
    ret

Z_Init:
    addi sp, sp, -32
    sd ra, 0(sp)
    addi a0, sp, 12         # size_ptr on stack
    jal ra, I_ZoneBase
    # Check if I_ZoneBase returned expected value
    li t0, 0x9568
    beq a0, t0, Z_success
    # Return whatever we got
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
    mv s2, a0               # s2 = size_ptr
    li a1, 1                # ** This becomes the "1" if not overwritten **
    sd ra, 24(sp)
    sd s0, 16(sp)
    sd s1, 8(sp)

    jal ra, M_Check
    bgtz a0, use_cmdline

    lui a0, 0x600
    lui a5, 0x600
    li s0, 6                # ** This is the "6" in the output (if read from s0) **
    sw a5, 0(s2)            # Store size at *s2

    jal ra, fake_malloc

    mv s1, a0               # Save malloc result to s1
    beqz a0, fail_null

    lw a2, 0(s2)            # Load size from *s2 into a2
    mv a1, a0               # Copy malloc result to a1

    # Verify a1 = malloc result
    li t0, 0x9568
    bne a1, t0, fail_a1

    # Verify a2 = size
    lui t0, 0x600
    bne a2, t0, fail_a2

    # Success - return malloc result
    mv a0, s1
    j done

use_cmdline:
    li a0, 77
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

M_Check:
    li a0, 0
    ret

fake_malloc:
    ld a4, -1912(gp)
    addi a0, a0, 15
    andi a0, a0, -16
    add a0, a0, a4
    sd a0, -1912(gp)
    mv a0, a4
    ret
