# Test file with invalid/unknown opcode
.section .text
.global _start
_start:
    li a0, 42           # Set a0 to something

    # Emit an invalid opcode (0x0000007F is not a valid RISC-V opcode)
    .word 0x0000007F

    # If we somehow get past that:
    li a0, 0
    li a7, 93
    ecall
