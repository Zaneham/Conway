; test_ecall_regs.asm - Check registers after execute_blocks with ECALL
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

    lea rcx, [code_buffer]
    mov rdx, 1048576
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    call init_block_cache

    lea rdi, [rv_regs]
    mov rcx, 32
    xor eax, eax
.clear:
    mov [rdi], rax
    add rdi, 8
    dec rcx
    jnz .clear

    xor edi, edi
    lea rsi, [test_program]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8, 10
    call execute_blocks

    ; Check what's in a0 (should be 42)
    mov rax, [rv_regs + 10*8]
    cmp rax, 42
    jne .check_a7

    ; a0 is 42, exit with 100 to signal success
    mov ecx, 100
    call ExitProcess

.check_a7:
    ; a0 wasn't 42, exit with a7 value to debug
    mov ecx, [rv_regs + 17*8]
    call ExitProcess
