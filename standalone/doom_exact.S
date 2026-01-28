# doom_exact.S - Exact reproduction of Doom's I_ZoneBase sequence
# Including the problematic li a1,1 before function call

.section .text
.global _start

_start:
    li sp, 0x6FFFF0

    # Set up s2 (size_ptr) like I_ZoneBase does
    li a0, 0x2000
    jal ra, test_zone

    # Check what test_zone returned in a0
    # If successful, a0 = 0. Otherwise it's an error code.
    li a7, 93
    ecall

test_zone:
    addi sp, sp, -32
    sd s2, 0(sp)
    sd ra, 24(sp)
    sd s0, 16(sp)
    sd s1, 8(sp)

    mv s2, a0               # s2 = size_ptr

    #--- Simulate M_CheckParmWithArgs call ---
    # This sets a1 to 1 before the call, just like Doom does
    lui a0, 0x40
    addi a0, a0, -712       # Format string (unused)
    li a1, 1                # a1 = 1 (this is the problematic value!)

    jal ra, fake_check      # Returns 0 in a0

    # After return, a0 = 0, but a1 may still be 1!
    bgtz a0, use_cmdline

    #--- Standard path (same as I_ZoneBase 1ac80-1aca4) ---
    lui a0, 0x600           # a0 = 0x600000 (size for malloc)
    lui a5, 0x600           # a5 = 0x600000
    li s0, 6                # s0 = 6 (this is the other problematic value!)
    sw a5, 0(s2)            # Store size at *s2

    jal ra, fake_malloc     # Returns 0x69568 in a0

    mv s1, a0               # Save to s1 (C.MV encoding)

    beqz a0, fail_null

    lw a2, 0(s2)            # Load size into a2 (should be 0x600000)
    mv a1, a0               # a1 = zone pointer (should be 0x69568)

    # At this point:
    # a1 SHOULD be 0x69568 (from mv a1, a0)
    # a2 SHOULD be 0x600000 (from lw a2, 0(s2))

    # Check a1 value
    li t0, 0x69568
    bne a1, t0, fail_a1     # If a1 != 0x69568, fail

    # Check a2 value
    lui t0, 0x600
    bne a2, t0, fail_a2     # If a2 != 0x600000, fail

    # Success
    li a0, 0
    j done

use_cmdline:
    li a0, 77
    j done

fail_null:
    li a0, 88
    j done

fail_a1:
    # Return a1 value shifted to see what we got
    mv a0, a1
    j done

fail_a2:
    # Return a2 >> 20 to see if we got 6
    srli a0, a2, 20
    addi a0, a0, 100        # Add 100 to distinguish from other codes
    j done

done:
    ld ra, 24(sp)
    ld s0, 16(sp)
    ld s1, 8(sp)
    ld s2, 0(sp)
    addi sp, sp, 32
    ret

fake_check:
    # Return 0 (not found)
    li a0, 0
    ret

fake_malloc:
    # Return a known pointer value
    li a0, 0x69568
    ret
