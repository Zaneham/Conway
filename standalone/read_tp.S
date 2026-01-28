# Read TP register value and return lower byte
.section .text
.globl _start

_start:
    # Read TP (should be 0x6E4D0 for strncasecmp_simple layout)
    mv a0, tp
    andi a0, a0, 0xFF   # Return lower byte (should be 0xD0 = 208)
    
    li a7, 93
    ecall
