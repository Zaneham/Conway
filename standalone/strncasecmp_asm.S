# strncasecmp_asm.S - Test strncasecmp behavior
# Exit code: 0 = PASS (strings don't match), 1 = FAIL (strings incorrectly match)

.section .text
.global _start

# Simple tolower: if char is A-Z, add 32
# a0 = char, returns result in a0
tolower:
    li t0, 'A'
    li t1, 'Z'
    blt a0, t0, tolower_done
    bgt a0, t1, tolower_done
    addi a0, a0, 32
tolower_done:
    ret

# strncasecmp(s1, s2, n) - compare n bytes case-insensitively
# a0 = s1, a1 = s2, a2 = n
# returns: 0 if equal, non-zero otherwise
strncasecmp:
    addi sp, sp, -32
    sd ra, 24(sp)
    sd s0, 16(sp)
    sd s1, 8(sp)
    sd s2, 0(sp)

    mv s0, a0       # s0 = s1
    mv s1, a1       # s1 = s2
    mv s2, a2       # s2 = n

cmp_loop:
    beqz s2, cmp_equal     # if n == 0, strings are equal

    lb t0, 0(s0)           # load byte from s1
    lb t1, 0(s1)           # load byte from s2

    # tolower(t0) -> t2
    mv a0, t0
    li t3, 'A'
    li t4, 'Z'
    blt a0, t3, skip_lower1
    bgt a0, t4, skip_lower1
    addi a0, a0, 32
skip_lower1:
    mv t2, a0

    # tolower(t1) -> t3
    mv a0, t1
    li t3, 'A'
    li t4, 'Z'
    blt a0, t3, skip_lower2
    bgt a0, t4, skip_lower2
    addi a0, a0, 32
skip_lower2:
    mv t3, a0

    # Compare lowercased bytes
    bne t2, t3, cmp_diff   # if different, return difference

    # Check if we hit null terminator
    beqz t0, cmp_equal     # if s1[i] == 0, strings are equal

    addi s0, s0, 1
    addi s1, s1, 1
    addi s2, s2, -1
    j cmp_loop

cmp_equal:
    li a0, 0
    j cmp_done

cmp_diff:
    sub a0, t2, t3         # return difference

cmp_done:
    ld ra, 24(sp)
    ld s0, 16(sp)
    ld s1, 8(sp)
    ld s2, 0(sp)
    addi sp, sp, 32
    ret

_start:
    li sp, 0x6FFF0         # Set up stack

    # Test: strncasecmp("F_END\0\0\0", "IMPXA1", 8)
    # These should NOT match
    la a0, str_fend
    la a1, str_impxa1
    li a2, 8
    call strncasecmp

    # a0 now has result
    # If a0 == 0, strings matched (FAIL)
    # If a0 != 0, strings didn't match (PASS)

    beqz a0, test_fail

    # PASS - exit with 0
    li a0, 0
    li a7, 93
    ecall

test_fail:
    # FAIL - exit with 1
    li a0, 1
    li a7, 93
    ecall

.section .rodata
str_fend:    .byte 'F', '_', 'E', 'N', 'D', 0, 0, 0
str_impxa1:  .asciz "IMPXA1"
