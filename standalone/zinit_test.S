# zinit_test.S - Exact simulation of Z_Init calling I_ZoneBase
# This mirrors the EXACT instruction sequence from Doom

.section .text
.global _start

_start:
    li sp, 0xFFF0
    li gp, 0x8000           # Scaled down gp

    # Initialize heap_ptr at gp-1912
    li t0, 0x9568
    sd t0, -1912(gp)

    # Call Z_Init (which calls I_ZoneBase)
    jal ra, Z_Init

    # Return result
    li a7, 93
    ecall

# Simulated Z_Init - matches Doom's Z_Init at 0x39b0e
Z_Init:
    # 39b0e: 1101          addi sp,sp,-32
    addi sp, sp, -32

    # 39b10: 0068          addi a0,sp,12
    addi a0, sp, 12         # size_ptr = stack address

    # 39b14: jal I_ZoneBase
    jal ra, I_ZoneBase

    # Check return value
    li t0, 0x9568
    beq a0, t0, Z_Init_success

    # Return what we got (should be 0x9568)
    addi sp, sp, 32
    ret

Z_Init_success:
    li a0, 0
    addi sp, sp, 32
    ret

# Simulated I_ZoneBase - matches Doom's I_ZoneBase at 0x1ac62
I_ZoneBase:
    # 1ac62: 1101          addi sp,sp,-32
    addi sp, sp, -32

    # 1ac64: e04a          sd s2,0(sp)
    sd s2, 0(sp)

    # 1ac66: 892a          mv s2,a0
    mv s2, a0               # s2 = size_ptr

    # 1ac68-1ac6e: lui/addi a0 (format string - we skip)
    # 1ac6c: 4585          li a1,1
    li a1, 1                # *** This is the "1" we see in output ***

    # 1ac72-1ac76: save ra, s0, s1
    sd ra, 24(sp)
    sd s0, 16(sp)
    sd s1, 8(sp)

    # 1ac78: jal M_CheckParmWithArgs (returns 0)
    jal ra, fake_M_CheckParm

    # 1ac7c: bgtz a0,... (not taken since a0=0)
    bgtz a0, use_cmdline

    # 1ac80: 00600537      lui a0,0x600
    lui a0, 0x600

    # 1ac84: 006007b7      lui a5,0x600
    lui a5, 0x600

    # 1ac88: 4419          li s0,6
    li s0, 6                # *** This is the "6" we see in output ***

    # 1ac8a: 00f92023      sw a5,0(s2)
    sw a5, 0(s2)            # Store size at *size_ptr

    # 1ac8e: jal malloc
    jal ra, fake_malloc

    # 1ac92: 84aa          mv s1,a0
    mv s1, a0               # Save malloc result

    # 1ac94: c10d          beqz a0,fail
    beqz a0, fail_null

    # 1ac96: 00092603      lw a2,0(s2)
    lw a2, 0(s2)            # Load size from *size_ptr

    # 1ac9a: 85aa          mv a1,a0
    mv a1, a0               # a1 = malloc result

    # At this point:
    # a1 SHOULD be 0x9568 (malloc result)
    # a2 SHOULD be 0x600000 (size)

    # Check a1
    li t0, 0x9568
    bne a1, t0, fail_a1

    # Check a2
    lui t0, 0x600
    bne a2, t0, fail_a2

    # Success - return malloc result (in s1)
    mv a0, s1
    j done

use_cmdline:
    li a0, 77
    j done

fail_null:
    li a0, 88
    j done

fail_a1:
    # Return a1 value to see what we got
    mv a0, a1
    j done

fail_a2:
    # Return shifted a2 to see what we got
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

fake_M_CheckParm:
    li a0, 0
    ret

fake_malloc:
    # Load heap_ptr, return it
    ld a4, -1912(gp)

    # Bump heap
    addi a0, a0, 15
    andi a0, a0, -16
    add a0, a0, a4
    sd a0, -1912(gp)

    mv a0, a4
    ret
