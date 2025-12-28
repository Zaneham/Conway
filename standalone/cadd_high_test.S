# Test C.ADD with high registers - mimics C-cadd-01 inst_3
.section .text
.global _start
_start:
    # Test case 3 from C-cadd-01:
    # li s8, 1
    # li s10, 1
    # slli s10, s10, 0x1d    # s10 = 0x20000000
    # not s10, s10           # s10 = 0xFFFFFFFFDFFFFFFF
    # c.add s10, s8          # s10 = s10 + 1 = 0xFFFFFFFFE0000000

    li s8, 1
    li s10, 1
    slli s10, s10, 0x1d
    not s10, s10
    c.add s10, s8

    # Expected: s10 = 0xFFFFFFFFE0000000
    li t0, 1
    slli t0, t0, 0x1d
    not t0, t0
    addi t0, t0, 1          # t0 = expected

    bne s10, t0, fail

    # All passed
    li a0, 0
    li a7, 93
    ecall

fail:
    li a0, 1
    li a7, 93
    ecall
