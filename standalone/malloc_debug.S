# malloc_debug.S - Debug what malloc returns
# Simplified version that tests the exact malloc path

.section .text
.global _start

_start:
    li sp, 0xFFF0

    # Set up gp (scaled down)
    li gp, 0x8000

    # Initialize heap_ptr at gp - 1912
    li t0, 0x9568
    sd t0, -1912(gp)

    # Verify initial store
    ld t1, -1912(gp)
    li a7, 93
    bne t0, t1, fail_init

    # Call malloc with 0x600000 (like Doom)
    lui a0, 0x600
    jal ra, test_malloc

    # Check what we got back
    # a0 should now be the old heap_ptr = 0x9568
    li t0, 0x9568
    beq a0, t0, success

    # Return what we actually got
    # If a0 is small, return it directly
    li t1, 256
    blt a0, t1, return_a0

    # Otherwise return a shifted version
    srli a0, a0, 8
    li a7, 93
    ecall

return_a0:
    li a7, 93
    ecall

success:
    li a0, 0
    li a7, 93
    ecall

fail_init:
    li a0, 91
    ecall

# Simplified malloc using gp-relative addressing
test_malloc:
    # Load heap_ptr from gp-1912
    ld a4, -1912(gp)

    # Align size to 16 bytes
    addi a0, a0, 15
    andi a0, a0, -16

    # Calculate new heap_ptr
    add a0, a0, a4

    # Store new heap_ptr
    sd a0, -1912(gp)

    # Return old heap_ptr
    mv a0, a4
    ret
