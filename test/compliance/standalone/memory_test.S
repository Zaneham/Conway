# Standalone Memory Tests for Conway
# Tests: LB, LH, LW, LD, LBU, LHU, LWU, SB, SH, SW, SD

.section .text
.global _start

_start:
    # Set up stack pointer to data area
    la      sp, test_data

    # ============ SD/LD Tests (64-bit) ============
    li      a0, 0x123456789ABCDEF0
    sd      a0, 0(sp)
    ld      a1, 0(sp)
    bne     a0, a1, fail

    # ============ SW/LW Tests (32-bit, sign extended) ============
    li      a0, 0x12345678
    sw      a0, 8(sp)
    lw      a1, 8(sp)           # Sign extends to 64-bit
    li      t0, 0x12345678
    bne     a1, t0, fail

    # Negative value test
    li      a0, 0xFFFFFFFF      # -1 in 32-bit
    sw      a0, 8(sp)
    lw      a1, 8(sp)           # Should sign-extend to 0xFFFFFFFFFFFFFFFF
    li      t0, -1
    bne     a1, t0, fail

    # ============ LWU Tests (32-bit, zero extended) ============
    li      a0, 0xFFFFFFFF
    sw      a0, 12(sp)
    lwu     a1, 12(sp)          # Zero extends
    li      t0, 0xFFFFFFFF      # Just 32 bits, no sign extension
    bne     a1, t0, fail

    # ============ SH/LH Tests (16-bit, sign extended) ============
    li      a0, 0x1234
    sh      a0, 16(sp)
    lh      a1, 16(sp)
    li      t0, 0x1234
    bne     a1, t0, fail

    li      a0, 0xFFFF          # -1 in 16-bit
    sh      a0, 16(sp)
    lh      a1, 16(sp)          # Sign extends to -1
    li      t0, -1
    bne     a1, t0, fail

    # ============ LHU Tests (16-bit, zero extended) ============
    li      a0, 0xFFFF
    sh      a0, 18(sp)
    lhu     a1, 18(sp)
    li      t0, 0xFFFF
    bne     a1, t0, fail

    # ============ SB/LB Tests (8-bit, sign extended) ============
    li      a0, 0x42
    sb      a0, 20(sp)
    lb      a1, 20(sp)
    li      t0, 0x42
    bne     a1, t0, fail

    li      a0, 0xFF            # -1 in 8-bit
    sb      a0, 20(sp)
    lb      a1, 20(sp)          # Sign extends to -1
    li      t0, -1
    bne     a1, t0, fail

    # ============ LBU Tests (8-bit, zero extended) ============
    li      a0, 0xFF
    sb      a0, 21(sp)
    lbu     a1, 21(sp)
    li      t0, 0xFF
    bne     a1, t0, fail

    # All tests passed
    li      a0, 0
    li      a7, 93
    ecall

fail:
    li      a0, 1
    li      a7, 93
    ecall

.section .data
.align 8
test_data:
    .space 256
