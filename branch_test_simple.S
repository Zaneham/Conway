# Test to verify branch logic
# Set a0 based on which path we take
.section .text
.global _start

_start:
    li      a0, 10          # Start with 10
    bne     x0, x0, taken   # Should NOT branch (0 == 0)
    li      a0, 20          # Not-taken path: a0 = 20
    j       done
taken:
    li      a0, 30          # Taken path: a0 = 30
done:
    li      a7, 93
    ecall
# Expected: exit(20) because BNE should NOT take branch
