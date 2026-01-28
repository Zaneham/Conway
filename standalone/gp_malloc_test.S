# gp_malloc_test.S - Test gp-relative addressing like malloc uses

.section .text
.global _start

# Simulate doom layout:
# gp = 0x68e00
# heap_ptr at gp-1912 = 0x68688
# Initial heap_ptr value = 0x69568

_start:
    li sp, 0x6FFFF0

    # Set up gp like doom does (simulated for our address space)
    # We'll use gp = 0x2800, heap_ptr at 0x2800 - 1912 = 0x2800 - 0x778 = 0x2088
    li gp, 0x2800

    # Store initial heap_ptr value at gp-1912
    li t0, 0x69568
    sd t0, -1912(gp)

    # Verify the store
    ld t1, -1912(gp)
    bne t0, t1, fail_store

    # Now call our malloc simulation
    li a0, 0x600000         # Request 6MB
    jal ra, gp_malloc

    # Verify result
    li t0, 0x69568          # Expected return value (original heap_ptr)
    bne a0, t0, fail_malloc

    # Success
    li a0, 0
    li a7, 93
    ecall

fail_store:
    li a0, 91
    li a7, 93
    ecall

fail_malloc:
    li a0, 92
    li a7, 93
    ecall

# Simplified malloc using gp-relative addressing (like doom's)
gp_malloc:
    # ld a4, -1912(gp)  - Load heap_ptr
    ld a4, -1912(gp)

    # Align size to 16 bytes
    addi a0, a0, 15
    andi a0, a0, -16

    # Calculate new heap_ptr
    add a0, a0, a4          # new_ptr = old_ptr + size

    # Store new heap_ptr
    sd a0, -1912(gp)

    # Return old heap_ptr
    mv a0, a4
    ret
