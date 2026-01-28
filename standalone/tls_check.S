.section .text
.globl _start

_start:
    # Read TP register
    mv a0, tp
    
    # Load first 8 bytes from TLS area
    # Try different offsets to find the locale data
    ld a1, 0(tp)
    ld a2, 8(tp)
    ld a3, 16(tp)
    
    # Return lower 8 bits of first TLS pointer
    # If TLS is working, this should be non-zero
    andi a0, a1, 0xFF
    
    # Exit syscall
    li a7, 93
    ecall
