; test_jal_simple.asm - Test JAL instruction PC update
bits 64
default rel

extern init_block_cache
extern execute_blocks
extern code_buffer
extern ExitProcess
extern VirtualAlloc
extern VirtualProtect
extern GetStdHandle
extern WriteFile

PAGE_EXECUTE_READWRITE  equ 0x40
PAGE_READWRITE          equ 0x04
MEM_COMMIT              equ 0x1000
MEM_RESERVE             equ 0x2000
STD_OUTPUT_HANDLE       equ -11

section .data
    msg_test    db "Testing JAL...", 13, 10, 0
    msg_pass    db "PASS: PC updated", 13, 10, 0
    msg_fail    db "FAIL: PC stuck", 13, 10, 0

section .bss
    old_protect     resd 1
    alignb 8
    guest_memory    resq 1
    stdout_handle   resq 1
    chars_written   resq 1
    rv_regs         resq 32
    rv_pc           resq 1

section .text
    global main

main:
    push rbp
    mov rbp, rsp
    sub rsp, 80

    ; Get stdout
    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [stdout_handle], rax

    ; Print test message
    mov rcx, [stdout_handle]
    lea rdx, [msg_test]
    mov r8d, 16
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Allocate guest memory
    xor ecx, ecx
    mov edx, 65536
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz .fail
    mov [guest_memory], rax

    ; Make code buffer executable
    lea rcx, [code_buffer]
    mov edx, 1048576
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    ; Init block cache
    call init_block_cache

    ; Write simple test code to guest memory at offset 0x1000
    ; JAL x1, 8  ; Jump forward 8 bytes
    ; at 0x1000: jal x1, 8 = 0x008000EF (jump to 0x1008)
    ; at 0x1008: addi a7, x0, 93 (exit syscall)
    ; at 0x100C: ecall
    mov rdi, [guest_memory]
    mov dword [rdi + 0x1000], 0x008000EF    ; jal x1, 8 (jumps to 0x1008)
    mov dword [rdi + 0x1004], 0x00000013    ; nop (addi x0, x0, 0) - should skip
    mov dword [rdi + 0x1008], 0x05D00893    ; addi a7, x0, 93
    mov dword [rdi + 0x100C], 0x00000073    ; ecall

    ; Clear registers
    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 32
.clr:
    mov [rdi + rcx*8 - 8], rax
    dec ecx
    jnz .clr

    ; Set a0 = 42 (will be exit code if we reach ecall)
    lea rax, [rv_regs]
    mov qword [rax + 10*8], 42

    ; Execute starting at PC 0x1000
    mov edi, 0x1000                     ; start PC
    mov rsi, [guest_memory]             ; code base
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8d, 10                         ; max blocks
    call execute_blocks

    ; Check PC - should be past 0x1000
    mov rax, [rv_pc]
    cmp rax, 0x1000
    jle .pc_stuck

    ; Print pass
    mov rcx, [stdout_handle]
    lea rdx, [msg_pass]
    mov r8d, 17
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Get exit code from a0
    lea rax, [rv_regs]
    mov ecx, [rax + 10*8]
    jmp .exit

.pc_stuck:
    mov rcx, [stdout_handle]
    lea rdx, [msg_fail]
    mov r8d, 16
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile
    mov ecx, 1
    jmp .exit

.fail:
    mov ecx, 255

.exit:
    add rsp, 80
    pop rbp
    sub rsp, 40
    call ExitProcess
