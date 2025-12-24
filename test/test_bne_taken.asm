; test_bne_taken.asm - BNE that IS taken
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
        dd 0x00500093       ; PC=0:  addi x1, x0, 5
        dd 0x00A00113       ; PC=4:  addi x2, x0, 10 (different from x1!)
        dd 0x00209463       ; PC=8:  bne x1, x2, 8 -> PC=16 (taken!)
        dd 0x00000000       ; PC=12: padding
        dd 0x00000063       ; PC=16: beq x0, x0, 0

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

    ; Execute 1 block
    xor edi, edi
    lea rsi, [test_program]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8, 1
    call execute_blocks

    ; Exit with PC - should be 16 if taken
    mov ecx, [rv_pc]
    call ExitProcess
