; sanity_test.asm - Test without translator
bits 64
default rel

section .data
    fmt: db "Hello: %d", 10, 0

section .text
    global main
    extern printf
    extern ExitProcess

main:
    push rbp
    mov rbp, rsp
    sub rsp, 64

    lea rcx, [fmt]
    mov edx, 42
    call printf

    xor ecx, ecx
    call ExitProcess
