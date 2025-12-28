# Test exit sequence - exactly as in arch tests
.section .text
.global _start
_start:
    # Set a0 to something non-zero first
    li a0, 42

    # Now mimic exit_cleanup exactly:
    # 8d0c: 4501          li a0,0
    # 8d0e: 05d00893      li a7,93
    # 8d12: 00000073      ecall

    .byte 0x01, 0x45        # C.LI a0, 0 (little endian: 4501)
    .byte 0x93, 0x08, 0xd0, 0x05  # ADDI a7, x0, 93
    .byte 0x73, 0x00, 0x00, 0x00  # ECALL
