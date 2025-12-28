# C.ADD test - verify high register handling
.section .text
.global _start
_start:
    # Test 1: Low registers - C.ADD t0, t0, t1
    li t0, 5
    li t1, 3
    c.add t0, t1          # t0 = 5 + 3 = 8
    li t2, 8
    bne t0, t2, fail

    # Test 2: High registers - C.ADD s10, s10, s8
    li s10, 10
    li s8, 20
    c.add s10, s8         # s10 = 10 + 20 = 30
    li t2, 30
    bne s10, t2, fail

    # Test 3: Mixed large values with high registers
    li s10, 0x7FFFFFFF    # Max positive 32-bit
    li s8, 1
    c.add s10, s8         # s10 = 0x80000000
    li t2, 0x80000000
    bne s10, t2, fail

    # All passed
    li a0, 0
    j done

fail:
    li a0, 1

done:
    # Exit - a0 has result (0=pass, 1=fail)
    ebreak
