# fib.S - Calculate Fibonacci(10) = 55 using only RV64I base instructions
# "The rabbit problem, solved by rabbits" - Leonardo of Pisa (probably)

.section .text
.global _start

# Fibonacci sequence: 0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, ...
# fib(0) = 0, fib(1) = 1, fib(10) = 55

_start:
    # a0 = previous (starts at 0)
    # a1 = current (starts at 1)
    # a2 = counter (counts down from 10)
    # a3 = temp for swap

    li      a0, 0           # fib(0) = 0
    li      a1, 1           # fib(1) = 1
    li      a2, 9           # iterations needed for fib(10): 9 iterations

    # If n == 0, return 0
    beqz    a2, ret_zero

loop:
    # temp = current
    # current = previous + current
    # previous = temp
    add     a3, a1, zero    # a3 = a1 (save current)
    add     a1, a0, a1      # a1 = a0 + a1 (new current)
    add     a0, a3, zero    # a0 = a3 (old current becomes previous)

    # Decrement counter and loop if not zero
    addi    a2, a2, -1
    bnez    a2, loop

    j       done

ret_zero:
    li      a1, 0

done:
    # a1 now contains fib(10) = 55
    # Move to a0 for exit code
    add     a0, a1, zero

    # Exit syscall
    li      a7, 93
    ecall

    # Should never reach here
spin:
    j       spin
