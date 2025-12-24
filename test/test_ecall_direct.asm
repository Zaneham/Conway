; test_ecall_direct.asm - Test ECALL translation directly
bits 64
default rel

extern init_block_cache
extern translate_block
extern code_buffer
extern ExitProcess
extern VirtualProtect

PAGE_EXECUTE_READWRITE equ 0x40
BLOCK_CODE_PTR      equ 16
BLOCK_EXIT_TYPE     equ 28
EXIT_ECALL          equ 4

section .data
    align 4
    test_program:
        dd 0x02A00513       ; addi a0, x0, 42    (x10 = 42)
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

    ; Clear registers
    lea rdi, [rv_regs]
    mov rcx, 32
    xor eax, eax
.clear:
    mov [rdi], rax
    add rdi, 8
    dec rcx
    jnz .clear

    ; Translate block
    xor edi, edi
    lea rsi, [test_program]
    call translate_block
    mov [rbp-8], rax        ; Save block pointer

    ; Check exit type
    cmp dword [rax + BLOCK_EXIT_TYPE], EXIT_ECALL
    jne .wrong_exit_type

    ; Set up state and execute
    lea rbx, [rv_regs]
    lea r15, [rv_pc]
    mov qword [rv_pc], 0

    mov rax, [rbp-8]
    mov rax, [rax + BLOCK_CODE_PTR]
    call rax

    ; Exit with a0 value (should be 42)
    mov ecx, [rv_regs + 10*8]
    call ExitProcess

.wrong_exit_type:
    ; Exit 255 if wrong exit type
    mov ecx, 255
    call ExitProcess
