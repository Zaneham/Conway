; test_pc_check.asm - Check what PC is after block execution
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
        ; Block 1: PC=0
        dd 0x00500093       ; PC=0: addi x1, x0, 5
        dd 0x00000463       ; PC=4: beq x0, x0, 8 -> should be PC=4+8=12

        dd 0x00000000       ; PC=8: padding
        dd 0x00000000       ; PC=12: padding

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

    ; Execute just 1 block
    xor edi, edi
    lea rsi, [test_program]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8, 1
    call execute_blocks

    ; Exit with the PC value - should be 12 if branch worked correctly
    ; (branch at PC=4 with offset 8 should land at PC=12)
    mov ecx, [rv_pc]
    call ExitProcess
