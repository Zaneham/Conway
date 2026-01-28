# auipc_gp_test.S - Minimal test for auipc gp

.section .text
.global _start

_start:
    # Set SP with LUI only (no ADDIW)
    lui sp, 0x70

    # Test AUIPC to GP with known PC and immediate
    # At this point, PC should be 0x1004
    auipc gp, 0x56          # gp = 0x1004 + 0x56000 = 0x57004

    # Print GP value via write syscall
    # First build hex string in memory at sp-32
    addi sp, sp, -32

    # We'll just verify by exiting with gp>>16 as exit code
    # If gp = 0x57004, then gp>>16 = 0x5 or 0x57
    srli a0, gp, 16         # a0 = gp >> 16
    andi a0, a0, 0xFF       # Keep low 8 bits
    # Expected: 0x57 = 87 decimal
    # But if gp = 0, then a0 = 0

    li a7, 93
    ecall

.section .rodata
