# Test if data at TLS vaddr is being loaded
# TLS for strncasecmp_simple.elf is at 0x6E4D0
# The first 8 bytes should be 0x70680 (not zero)
.section .text
.globl _start

_start:
    # Load data directly from TLS vaddr (0x6E4D0)
    li t0, 0x6E4D0
    ld a0, 0(t0)
    
    # If TLS loaded correctly, a0 = 0x70680
    # Return lower byte (should be 0x80, not 0x00)
    andi a0, a0, 0xFF
    
    # Exit syscall
    li a7, 93
    ecall
