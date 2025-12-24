; test_exec_loop.asm - Test the execute_blocks loop
; Multiple blocks executing in sequence
bits 64
default rel

extern init_block_cache
extern execute_blocks
extern code_buffer
extern ExitProcess
extern VirtualProtect

PAGE_EXECUTE_READWRITE equ 0x40

section .data
    ; Program with 2 blocks:
    ; Block 1 (PC=0):
    ;   addi x1, x0, 5      ; x1 = 5
    ;   addi x2, x0, 10     ; x2 = 10
    ;   jal x0, 8           ; jump to PC=16 (block 2), don't save return
    ;
    ; Block 2 (PC=16):
    ;   add x3, x1, x2      ; x3 = 15
    ;   addi x4, x0, 99     ; x4 = 99 (marker that we reached block 2)
    ;   beq x0, x0, 0       ; branch to self (infinite loop - but we limit blocks)
    ;
    ; Expected: x1=5, x2=10, x3=15, x4=99

    align 4
    test_program:
        ; Block 1: PC 0-12
        dd 0x00500093       ; PC=0:  addi x1, x0, 5
        dd 0x00A00113       ; PC=4:  addi x2, x0, 10
        dd 0x0080006F       ; PC=8:  jal x0, 8 (jump to PC 16)
        dd 0x00000000       ; PC=12: padding

        ; Block 2: PC 16-28
        dd 0x002081B3       ; PC=16: add x3, x1, x2
        dd 0x06300213       ; PC=20: addi x4, x0, 99
        dd 0x00000063       ; PC=24: beq x0, x0, 0 (branch to self)

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
    mov [rbp-8], rbx
    mov [rbp-16], r12

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
    ; RDI = start PC
    ; RSI = guest memory
    ; RDX = rv_regs
    ; RCX = rv_pc pointer
    ; R8  = max blocks (2 blocks should be enough)
    xor edi, edi                ; start PC = 0
    lea rsi, [test_program]     ; guest memory
    lea rdx, [rv_regs]          ; register file
    lea rcx, [rv_pc]            ; PC pointer
    mov r8, 3                   ; max 3 blocks (block1, block2, then block2 again which hits limit)
    call execute_blocks

    ; Check results
    lea rbx, [rv_regs]

    ; x1 should be 5
    cmp qword [rbx + 1*8], 5
    jne .fail

    ; x2 should be 10
    cmp qword [rbx + 2*8], 10
    jne .fail

    ; x3 should be 15
    cmp qword [rbx + 3*8], 15
    jne .fail

    ; x4 should be 99 (proves we reached block 2)
    cmp qword [rbx + 4*8], 99
    jne .fail

    ; Success! Exit with x3 value
    mov ecx, [rbx + 3*8]        ; Should be 15
    call ExitProcess

.fail:
    mov ecx, 255
    call ExitProcess
