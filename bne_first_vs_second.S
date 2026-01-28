# Test: BNE at PC 0 vs PC 4
.section .text
.global _start

_start:
    # BNE at PC 0 with offset to skip one instruction
    bne     x0, x0, skip1   # If taken (wrong): skip next
    li      a0, 1           # This should execute: a0 = 1
skip1:
    # Now BNE at PC 8 (not 0) with similar structure
    bne     x0, x0, skip2   # If taken (wrong): skip next
    addi    a0, a0, 2       # This should execute: a0 = 3
skip2:
    li      a7, 93
    ecall
# Expected: exit(3) if both work
# Exit(0) if first BNE wrongly branches
# Exit(1) if second BNE wrongly branches
# Exit(2) if both wrongly branch (but 2nd also skips addi)
