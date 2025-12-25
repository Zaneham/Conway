# Standalone Branch Tests for Conway
# Tests: BEQ, BNE, BLT, BGE, BLTU, BGEU, JAL, JALR

.section .text
.global _start

_start:
    # ============ BEQ Tests ============
    li      a0, 42
    li      a1, 42
    beq     a0, a1, beq_pass
    j       fail
beq_pass:

    li      a0, 42
    li      a1, 43
    beq     a0, a1, fail        # Should NOT branch

    # ============ BNE Tests ============
    li      a0, 42
    li      a1, 43
    bne     a0, a1, bne_pass
    j       fail
bne_pass:

    li      a0, 42
    li      a1, 42
    bne     a0, a1, fail        # Should NOT branch

    # ============ BLT Tests (signed) ============
    li      a0, -10
    li      a1, 10
    blt     a0, a1, blt_pass    # -10 < 10
    j       fail
blt_pass:

    li      a0, 10
    li      a1, -10
    blt     a0, a1, fail        # 10 !< -10

    # ============ BGE Tests (signed) ============
    li      a0, 10
    li      a1, -10
    bge     a0, a1, bge_pass1   # 10 >= -10
    j       fail
bge_pass1:

    li      a0, 42
    li      a1, 42
    bge     a0, a1, bge_pass2   # 42 >= 42
    j       fail
bge_pass2:

    # ============ BLTU Tests (unsigned) ============
    li      a0, 5
    li      a1, 10
    bltu    a0, a1, bltu_pass   # 5 < 10 (unsigned)
    j       fail
bltu_pass:

    li      a0, -1              # Max unsigned value
    li      a1, 10
    bltu    a0, a1, fail        # Max unsigned !< 10

    # ============ BGEU Tests (unsigned) ============
    li      a0, -1              # Max unsigned value
    li      a1, 10
    bgeu    a0, a1, bgeu_pass   # Max unsigned >= 10
    j       fail
bgeu_pass:

    # ============ JAL Tests ============
    jal     ra, jal_target
    li      t0, 0
    bne     t0, zero, fail      # t0 should be 0 (set by jal_target)
    j       jal_done
jal_target:
    li      t0, 0               # Mark that we got here
    jalr    zero, ra, 0         # Return (jump to ra)
jal_done:

    # ============ JALR Tests ============
    la      t1, jalr_target
    jalr    ra, t1, 0
    li      t0, 0
    bne     t0, zero, fail
    j       jalr_done
jalr_target:
    li      t0, 0
    jalr    zero, ra, 0
jalr_done:

    # All tests passed
    li      a0, 0
    li      a7, 93
    ecall

fail:
    li      a0, 1
    li      a7, 93
    ecall
