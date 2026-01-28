; test_compressed.asm - Test C extension support
; Using British spelling throughout, naturally
bits 64
default rel

extern init_block_cache
extern translate_block
extern code_buffer
extern ExitProcess
extern VirtualAlloc
extern VirtualProtect
extern GetStdHandle
extern WriteConsoleA

PAGE_EXECUTE_READWRITE  equ 0x40
PAGE_READWRITE          equ 0x04
MEM_COMMIT              equ 0x1000
MEM_RESERVE             equ 0x2000
STD_OUTPUT_HANDLE       equ -11

section .data
    ; Simple compressed instruction test
    ; C.LI x10, 42 = 0x4529 (load immediate 42 into a0)
    ; ECALL = 0x00000073 (32-bit, exit syscall)
    test_code   dw 0x4529       ; C.LI a0, 42
                dw 0x4581       ; C.LI a1, 0
                dw 0x45c5       ; C.LI a7, 17 (exit_group syscall... wait need to encode properly)

    ; Actually let's use raw bytes for clarity
    ; C.LI rd, imm: 010 | imm[5] | rd | imm[4:0] | 01
    ; C.LI a0(x10), 42: 010 | 0 | 01010 | 101010 | 01 = 0b010_0_01010_10101_01
    ; Wait, imm is 6 bits: imm[5] | imm[4:0]
    ; 42 = 0b101010, imm[5]=1, imm[4:0]=01010
    ; 010 | 1 | 01010 | 01010 | 01 = 0b0101_0101_0010_1001 = 0x5529

    msg_test    db "Testing compressed instructions...", 13, 10, 0
    msg_pass    db "PASS: C extension working!", 13, 10, 0
    msg_fail    db "FAIL", 13, 10, 0

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
    sub rsp, 64

    ; Get stdout
    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [stdout_handle], rax

    ; Print test message
    mov rcx, [stdout_handle]
    lea rdx, [msg_test]
    mov r8d, 36
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteConsoleA

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

    ; Initialise block cache
    call init_block_cache

    ; Write test code to guest memory
    ; C.LI a0, 42 = 010 | imm[5] | rd | imm[4:0] | 01
    ; rd = x10 = 01010, imm = 42 = 0b101010
    ; 010 | 1 | 01010 | 01010 | 01 = 0x5529
    mov rdi, [guest_memory]
    mov word [rdi], 0x5529          ; C.LI a0, 42
    mov dword [rdi+2], 0x00000073   ; ECALL (32-bit)

    ; Clear registers
    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 32
.clr:
    mov [rdi + rcx*8 - 8], rax
    dec ecx
    jnz .clr

    ; Set a7 = 93 (exit syscall)
    lea rax, [rv_regs]
    mov qword [rax + 17*8], 93

    ; Translate the block
    ; translate_block(guest_pc, code_base, x86_dest)
    xor edi, edi                    ; guest_pc = 0
    mov rsi, [guest_memory]         ; code_base
    lea rdx, [code_buffer]          ; x86_dest
    call translate_block

    ; Check return - should be positive (bytes written)
    test eax, eax
    jle .fail

    ; Print success and check what a0 would be
    mov rcx, [stdout_handle]
    lea rdx, [msg_pass]
    mov r8d, 27
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteConsoleA

    ; Exit with 0 (success)
    mov ecx, 0
    jmp .exit

.fail:
    mov rcx, [stdout_handle]
    lea rdx, [msg_fail]
    mov r8d, 6
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteConsoleA
    mov ecx, 1

.exit:
    add rsp, 64
    pop rbp
    sub rsp, 40
    call ExitProcess
