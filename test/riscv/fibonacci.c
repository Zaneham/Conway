// fibonacci.c - A simple Fibonacci calculator for Conway
// "The Fibonacci sequence, nature's way of saying 'I can count'"

// Calculate the nth Fibonacci number iteratively
// We use this instead of recursion because we don't have a proper stack yet
int fibonacci(int n) {
    if (n <= 1) return n;

    int a = 0;
    int b = 1;
    int i;

    for (i = 2; i <= n; i++) {
        int temp = a + b;
        a = b;
        b = temp;
    }

    return b;
}

// Entry point - calculate fib(10) = 55
// We'll return the result in a0 (x10) for the test to verify
void _start() {
    int result = fibonacci(10);

    // Exit syscall: a7 = 93, a0 = exit code
    register long a7 asm("a7") = 93;
    register long a0 asm("a0") = result;
    asm volatile("ecall" : : "r"(a7), "r"(a0));

    // Should never reach here
    while(1);
}
