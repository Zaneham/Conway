; test_branch_simple.asm - Absolute simplest branch test
bits 64
default rel

extern init_block_cache
extern translate_block
extern code_buffer
extern ExitProcess
extern VirtualProtect

PAGE_EXECUTE_READWRITE equ 0x40
BLOCK_CODE_PTR equ 16

section .data
    ; One block: set x1=5, branch to self
    align 4
    test_program:
        dd 0x00500093       ; PC=0: addi x1, x0, 5
        dd 0x00000063       ; PC=4: beq x0, x0, 0 (loop)

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

    ; Init cache
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

    ; Translate single block
    xor edi, edi
    lea rsi, [test_program]
    call translate_block
    mov [rbp-8], rax            ; Save block pointer

    ; Set up state
    lea rbx, [rv_regs]
    lea r15, [rv_pc]
    mov qword [rv_pc], 0

    ; Execute block
    mov rax, [rbp-8]
    mov rax, [rax + BLOCK_CODE_PTR]
    call rax

    ; Exit with x1 value - should be 5
    mov ecx, [rv_regs + 1*8]
    call ExitProcess
