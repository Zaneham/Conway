# fp_basic.S - Basic floating-point test
# Tests FLW, FSW, FADD.S, FMUL.S, FCVT

.section .data
.align 4
float_2:    .float 2.0
float_3:    .float 3.0
float_5:    .float 5.0
float_6:    .float 6.0
result:     .float 0.0

.section .text
.global _start

_start:
    # Load address of our data
    la      a0, float_2

    # Test 1: Load 2.0 and 3.0
    flw     f0, 0(a0)           # f0 = 2.0
    flw     f1, 4(a0)           # f1 = 3.0

    # Test 2: Add them - should get 5.0
    fadd.s  f2, f0, f1          # f2 = 2.0 + 3.0 = 5.0

    # Test 3: Multiply - should get 6.0
    fmul.s  f3, f0, f1          # f3 = 2.0 * 3.0 = 6.0

    # Test 4: Convert to integer
    fcvt.w.s a1, f2             # a1 = int(f2) = 5
    fcvt.w.s a2, f3             # a2 = int(f3) = 6

    # Check results
    li      t0, 5
    bne     a1, t0, fail1       # f2 should be 5

    li      t0, 6
    bne     a2, t0, fail2       # f3 should be 6

    # All tests passed
    li      a0, 0
    j       exit

fail1:
    li      a0, 1
    j       exit

fail2:
    li      a0, 2
    j       exit

exit:
    li      a7, 93
    ecall

spin:
    j       spin
