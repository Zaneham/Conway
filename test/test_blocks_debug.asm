; test_blocks_debug.asm - Minimal block cache debug
bits 64
default rel

extern init_block_cache
extern translate_block
extern lookup_block
extern block_cache
extern code_buffer
extern ExitProcess
extern VirtualProtect

PAGE_EXECUTE_READWRITE equ 0x40
BLOCK_CODE_PTR      equ 16

section .data
    align 4
    test_program:
        dd 0x00A00093       ; addi x1, x0, 10
        dd 0x00000463       ; beq x0, x0, 8 (always branch, ends block)

section .bss
    old_protect resd 1
    rv_regs     resq 32
    rv_pc       resq 1

section .text
    global main

main:
    push rbp
    mov rbp, rsp
    sub rsp, 64

    ; Stage 1: Make code buffer executable
    lea rcx, [code_buffer]
    mov rdx, 1048576
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    ; Exit 1 = after VirtualProtect
    ; mov ecx, 1
    ; call ExitProcess

    ; Stage 2: Init cache
    call init_block_cache

    ; Exit 2 = after init
    ; mov ecx, 2
    ; call ExitProcess

    ; Stage 3: Translate block
    xor edi, edi                ; PC = 0
    lea rsi, [test_program]
    call translate_block
    mov [rbp-8], rax            ; Save block pointer

    ; Exit 3 = after translate
    ; mov ecx, 3
    ; call ExitProcess

    ; Stage 4: Set up state and execute
    lea rbx, [rv_regs]
    lea r15, [rv_pc]
    mov qword [rv_pc], 0

    ; Get code pointer
    mov rax, [rbp-8]
    mov rax, [rax + BLOCK_CODE_PTR]

    ; Execute
    call rax

    ; Exit with x1 value (should be 10)
    mov ecx, [rv_regs + 1*8]
    call ExitProcess
