; test_ecall_simple.asm - Simple ECALL test
bits 64
default rel

extern init_block_cache
extern execute_blocks
extern code_buffer
extern ExitProcess
extern VirtualProtect

PAGE_EXECUTE_READWRITE equ 0x40

section .data
    align 4
    test_program:
        dd 0x02A00513       ; addi a0, x0, 42    (x10 = 42)
        dd 0x05D00893       ; addi a7, x0, 93    (x17 = 93 = exit)
        dd 0x00000073       ; ecall

section .bss
    old_protect resd 1
    alignb 8
    rv_regs     resq 32
    rv_pc       resq 1

section .text
    global main

main:
    push rbp
    mov rbp, rsp
    sub rsp, 64

    ; Make code buffer executable
    lea rcx, [code_buffer]
    mov rdx, 1048576
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    call init_block_cache

    ; Clear registers
    lea rdi, [rv_regs]
    mov rcx, 32
    xor eax, eax
.clear:
    mov [rdi], rax
    add rdi, 8
    dec rcx
    jnz .clear

    ; Execute
    xor edi, edi
    lea rsi, [test_program]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8, 10
    call execute_blocks

    ; Exit with a0 value (should be 42)
    mov ecx, [rv_regs + 10*8]
    call ExitProcess
