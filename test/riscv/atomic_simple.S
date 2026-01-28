# atomic_simple.S - Minimal atomic test
# Just test AMOADD which is simplest

.section .data
.align 8
counter:    .dword 100

.section .text
.global _start

_start:
    # Test AMOADD.D - add 50 to counter (100), should get 150
    la      a0, counter             # a0 = address of counter
    li      t0, 50                  # t0 = 50
    amoadd.d a1, t0, (a0)           # a1 = old (100), counter = 150

    # a1 should be 100 (old value)
    li      t1, 100
    bne     a1, t1, fail

    # counter should now be 150
    ld      t0, 0(a0)
    li      t1, 150
    bne     t0, t1, fail

    # Success!
    li      a0, 0
    j       exit

fail:
    li      a0, 1
    j       exit

exit:
    li      a7, 93
    ecall

spin:
    j       spin
