# doom_gp_small.S - Test with scaled-down addresses that fit in 64KB
# Instead of:
#   gp = 0x68e00, heap_ptr at gp-1912 = 0x68688
# We use:
#   gp = 0x8000, heap_ptr at gp-1912 = 0x7888

.section .text
.global _start

_start:
    li sp, 0xFFF0           # Stack near top of 64KB

    # Set up gp with scaled-down address
    li gp, 0x8000           # gp = 32KB

    # Initialize heap_ptr at gp - 1912
    li t0, 0x9568           # Scaled heap_ptr
    sd t0, -1912(gp)

    # Verify the store worked
    ld t1, -1912(gp)
    bne t0, t1, fail_store

    # Simulate Z_Init: create size_ptr on stack
    addi sp, sp, -32
    addi a0, sp, 12           # size_ptr = sp + 12 (like Z_Init)

    jal ra, test_izone

    # Result in a0
    li a7, 93
    ecall

test_izone:
    addi sp, sp, -32
    sd s2, 0(sp)
    sd ra, 24(sp)
    sd s0, 16(sp)
    sd s1, 8(sp)

    mv s2, a0                 # s2 = size_ptr (from stack)

    # Simulate M_CheckParmWithArgs call
    lui a0, 0x40
    addi a0, a0, -712
    li a1, 1                  # a1 = 1 (problematic value)

    jal ra, fake_check

    bgtz a0, use_cmdline

    # Standard path - set up malloc request
    lui a0, 0x600             # a0 = 0x600000 (size)
    lui a5, 0x600             # a5 = 0x600000
    li s0, 6                  # s0 = 6 (string index)
    sw a5, 0(s2)              # Store size at *size_ptr (stack location)

    jal ra, real_malloc       # Uses gp-relative addressing

    mv s1, a0                 # C.MV encoding

    beqz a0, fail_null

    # Load size from stack location
    lw a2, 0(s2)              # Should load 0x600000

    # Copy malloc result to a1
    mv a1, a0                 # Should copy the heap_ptr

    # Now check the values - a1 should be 0x9568, a2 should be 0x600000
    li t0, 0x9568
    bne a1, t0, fail_a1

    lui t0, 0x600
    bne a2, t0, fail_a2

    # Success!
    li a0, 0
    j done

use_cmdline:
    li a0, 77
    j done

fail_null:
    li a0, 88
    j done

fail_store:
    li a0, 91
    li a7, 93
    ecall

fail_a1:
    # Return what a1 actually was
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

fake_check:
    li a0, 0
    ret

# Real malloc simulation using gp-relative addressing
real_malloc:
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
