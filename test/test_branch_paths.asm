; test_branch_paths.asm - Test conditional branch taken/not-taken paths
; Verifies execute_blocks handles branch conditions correctly
bits 64
default rel

extern init_block_cache
extern execute_blocks
extern code_buffer
extern ExitProcess
extern VirtualProtect

PAGE_EXECUTE_READWRITE equ 0x40

section .data
    ; Program testing both branch paths:
    ;
    ; Block 1 (PC=0):
    ;   addi x1, x0, 5      ; x1 = 5
    ;   addi x2, x0, 5      ; x2 = 5
    ;   beq x1, x2, 12      ; if x1==x2, jump to PC=20 (block 2)
    ;   addi x10, x0, 1     ; NOT REACHED if branch taken
    ;
    ; Block 2 (PC=20):
    ;   addi x3, x0, 10     ; x3 = 10 (marker: we took the branch)
    ;   bne x1, x2, 12      ; if x1!=x2 (false), jump to PC=36
    ;   addi x4, x0, 20     ; x4 = 20 (marker: we did NOT take bne)
    ;   beq x0, x0, 0       ; infinite loop
    ;
    ; Expected: x1=5, x2=5, x3=10, x4=20, x10=0

    align 4
    test_program:
        ; Block 1: PC 0-16
        dd 0x00500093       ; PC=0:  addi x1, x0, 5
        dd 0x00500113       ; PC=4:  addi x2, x0, 5
        dd 0x00208663       ; PC=8:  beq x1, x2, 12 -> PC=20
        dd 0x00100513       ; PC=12: addi x10, x0, 1 (should NOT execute)
        dd 0x00000000       ; PC=16: padding

        ; Block 2: PC 20-36
        dd 0x00A00193       ; PC=20: addi x3, x0, 10
        dd 0x00209663       ; PC=24: bne x1, x2, 12 (should NOT branch)
        dd 0x01400213       ; PC=28: addi x4, x0, 20
        dd 0x00000063       ; PC=32: beq x0, x0, 0 (loop)

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
    xor edi, edi                ; start PC = 0
    lea rsi, [test_program]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8, 4                   ; max 4 blocks
    call execute_blocks

    ; Verify results
    lea rbx, [rv_regs]

    ; x1 should be 5
    cmp qword [rbx + 1*8], 5
    jne .fail

    ; x2 should be 5
    cmp qword [rbx + 2*8], 5
    jne .fail

    ; x3 should be 10 (proves we took beq branch)
    cmp qword [rbx + 3*8], 10
    jne .fail

    ; x4 should be 20 (proves we did NOT take bne branch)
    cmp qword [rbx + 4*8], 20
    jne .fail

    ; x10 should be 0 (proves we skipped the unreached code)
    cmp qword [rbx + 10*8], 0
    jne .fail

    ; Success!
    mov ecx, 0
    call ExitProcess

.fail:
    mov ecx, 255
    call ExitProcess
