# fib_bench.S - Fibonacci(30) = 832040 for benchmarking
# "Making CPUs sweat since the Middle Ages"

.section .text
.global _start

# Fibonacci sequence using iteration
# fib(30) = 832040

_start:
    # a0 = previous (starts at 0)
    # a1 = current (starts at 1)
    # a2 = counter (counts down from 30)

    li      a0, 0           # fib(0) = 0
    li      a1, 1           # fib(1) = 1
    li      a2, 29          # iterations needed for fib(30): 29 iterations

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
    # a1 now contains fib(30) = 832040
    # For exit code, we'll return fib(30) mod 256 = 232 (0xE8)
    andi    a0, a1, 0xFF

    # Exit syscall
    li      a7, 93
    ecall

spin:
    j       spin
