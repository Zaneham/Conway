; test_beq_simple.asm - Simplest BEQ taken test
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
        ; Block 1: addi + beq
        dd 0x00500093       ; PC=0:  addi x1, x0, 5
        dd 0x00500113       ; PC=4:  addi x2, x0, 5 (same as x1!)
        dd 0x00208463       ; PC=8:  beq x1, x2, 8 -> PC=16 (taken)

        dd 0x00000000       ; PC=12: padding

        ; Block 2: marker
        dd 0x00A00193       ; PC=16: addi x3, x0, 10
        dd 0x00000063       ; PC=20: beq x0, x0, 0 (loop)

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

    ; Execute 2 blocks
    xor edi, edi
    lea rsi, [test_program]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8, 2
    call execute_blocks

    ; Exit with x3 - should be 10 if branch worked
    mov ecx, [rv_regs + 3*8]
    call ExitProcess
