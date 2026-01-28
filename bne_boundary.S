# Test boundary between offset 12 and 16
.section .text
.global _start

_start:
    # Test offset 12 (should work)
    bne     x0, x0, test2
    li      a0, 1           # PC 4
    li      a7, 93          # PC 8
test2:                      # PC 12 - offset 12 target
    # Test offset 16 from here (PC 12 + offset should be 28 = 0x1C)
    # Actually let's just test if we survived the first
    li      a0, 100
    bne     x0, x0, fail    # offset 16 from PC 16
    li      a0, 0           # PC 20
    li      a7, 93          # PC 24
    nop                     # PC 28
    ecall                   # PC 32
fail:                       # PC 36
    li      a0, 1
    li      a7, 93
    ecall
