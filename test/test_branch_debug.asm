; test_branch_debug.asm - Debug branch paths
bits 64
default rel

extern init_block_cache
extern execute_blocks
extern code_buffer
extern ExitProcess
extern VirtualProtect

PAGE_EXECUTE_READWRITE equ 0x40

section .data
    ; Simple test: just set x1=5 and branch
    align 4
    test_program:
        dd 0x00500093       ; PC=0:  addi x1, x0, 5
        dd 0x00000463       ; PC=4:  beq x0, x0, 8 (always branch to PC=12)
        dd 0x00000000       ; PC=8:  padding (should NOT reach)
        dd 0x00A00113       ; PC=12: addi x2, x0, 10
        dd 0x00000063       ; PC=16: beq x0, x0, 0 (loop)

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

    ; Execute blocks
    xor edi, edi
    lea rsi, [test_program]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8, 3
    call execute_blocks

    ; Exit with x2 value - should be 10 if branch worked
    mov ecx, [rv_regs + 2*8]
    call ExitProcess
