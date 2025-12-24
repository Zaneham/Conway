; test_ecall_block.asm - Debug block translation with ECALL
bits 64
default rel

extern init_block_cache
extern translate_block
extern code_buffer
extern ExitProcess
extern VirtualProtect

PAGE_EXECUTE_READWRITE equ 0x40
BLOCK_CODE_PTR      equ 16
BLOCK_CODE_SIZE     equ 24
BLOCK_EXIT_TYPE     equ 28
EXIT_ECALL          equ 4

section .data
    align 4
    test_program:
        dd 0x02A00513       ; addi a0, x0, 42    (x10 = 42)
        dd 0x05D00893       ; addi a7, x0, 93    (x17 = 93)
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

    ; Translate block
    xor edi, edi
    lea rsi, [test_program]
    call translate_block

    test rax, rax
    jz .no_block

    mov [rbp-8], rax

    ; Check exit type - should be EXIT_ECALL (4)
    mov eax, [rax + BLOCK_EXIT_TYPE]
    cmp eax, EXIT_ECALL
    jne .wrong_exit

    ; Check code size (should be reasonable)
    mov rax, [rbp-8]
    mov eax, [rax + BLOCK_CODE_SIZE]
    cmp eax, 5
    jl .too_small
    cmp eax, 200
    jg .too_big

    ; Exit with code size (for debugging)
    mov ecx, eax
    call ExitProcess

.no_block:
    mov ecx, 250
    call ExitProcess

.wrong_exit:
    ; Exit with exit type + 100
    add eax, 100
    mov ecx, eax
    call ExitProcess

.too_small:
    mov ecx, 251
    call ExitProcess

.too_big:
    mov ecx, 252
    call ExitProcess
