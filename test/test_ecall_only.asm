; test_ecall_only.asm - Just ECALL, nothing else
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
        dd 0x00000073       ; ecall (just this)

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

    ; Clear registers and set a0=42, a7=93 manually
    lea rdi, [rv_regs]
    mov rcx, 32
    xor eax, eax
.clear:
    mov [rdi], rax
    add rdi, 8
    dec rcx
    jnz .clear

    ; Set a0 = 42, a7 = 93
    mov qword [rv_regs + 10*8], 42
    mov qword [rv_regs + 17*8], 93

    xor edi, edi
    lea rsi, [test_program]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8, 10
    call execute_blocks

    ; If we get here with a0 still 42, syscall handler worked
    mov rax, [rv_regs + 10*8]
    cmp rax, 42
    je .success

    ; a0 changed, exit with its value
    mov ecx, eax
    call ExitProcess

.success:
    mov ecx, 100
    call ExitProcess
