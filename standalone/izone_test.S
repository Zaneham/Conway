# izone_test.S - Exact sequence from I_ZoneBase
# Tests: function calls, C.MV, LW, and argument passing

.section .text
.global _start

_start:
    li sp, 0x6FFFF0

    # Set up size_ptr at 0x2000
    li a0, 0x2000
    jal ra, test_zone

    # Exit with a0 (should be 0 for success)
    li a7, 93
    ecall

# Mimics I_ZoneBase
test_zone:
    addi sp, sp, -32
    sd s2, 0(sp)
    sd ra, 24(sp)
    sd s0, 16(sp)
    sd s1, 8(sp)

    mv s2, a0               # s2 = size_ptr

    # Call fake M_CheckParmWithArgs
    li a0, 0x40000
    addi a0, a0, -712       # Format string (unused)
    li a1, 1                # Second arg = 1

    # Call fake check function (returns 0 = not found)
    jal ra, fake_check

    # bgtz a0 would skip - we simulate not found (a0 <= 0)
    bgtz a0, use_cmdline

    # Standard path: allocate 6MB zone
    lui a0, 0x600           # a0 = 0x600000
    lui a5, 0x600           # a5 = 0x600000
    li s0, 6                # s0 = 6 (for error message)
    sw a5, 0(s2)            # Store size

    jal ra, fake_malloc     # Call malloc - should return 0x69568

    mv s1, a0               # Save result

    beqz a0, fail_null      # Check NULL

    lw a2, 0(s2)            # Load size into a2 (should be 0x600000)
    mv a1, a0               # a1 = zone pointer (should be 0x69568)

    # Now verify values
    # a1 should be 0x69568
    li t0, 0x69568
    bne a1, t0, fail_a1

    # a2 should be 0x600000
    lui t0, 0x600
    bne a2, t0, fail_a2

    # Success
    li a0, 0
    j done

use_cmdline:
    li a0, 77               # Unexpected path
    j done

fail_null:
    li a0, 88
    j done

fail_a1:
    # Return actual a1 value for debugging (shifted)
    srli a0, a1, 0          # a0 = a1
    ori a0, a0, 0x40        # Mark as fail_a1 (64)
    j done

fail_a2:
    # Return a2 >> 20 for debugging
    srli a0, a2, 20
    addi a0, a0, 80         # Mark as fail_a2 (80+)
    j done

done:
    ld ra, 24(sp)
    ld s0, 16(sp)
    ld s1, 8(sp)
    ld s2, 0(sp)
    addi sp, sp, 32
    ret

fake_check:
    li a0, 0                # Return 0 (not found)
    ret

fake_malloc:
    # Return a known value like real malloc would
    li a0, 0x69568
    ret
