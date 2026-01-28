# Test loading data via TP register
# Expected: TP set by test harness, data at that address should be non-zero
.section .text
.globl _start

_start:
    # TP should be set by test harness to TLS base (e.g., 0x6E4D0)
    # Load first 8 bytes via TP
    ld a0, 0(tp)
    
    # Return lower byte (should be 0x80 for 0x70680)
    andi a0, a0, 0xFF
    
    # Exit
    li a7, 93
    ecall
