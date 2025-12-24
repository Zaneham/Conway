; test_phase4.asm - Phase 4 System Tests
; Tests ECALL, CSR, and FENCE instructions
bits 64
default rel

extern init_block_cache
extern execute_blocks
extern code_buffer
extern ExitProcess
extern GetStdHandle
extern WriteConsoleA
extern VirtualProtect

PAGE_EXECUTE_READWRITE equ 0x40

section .data
    msg_header      db "=== Phase 4: System Tests ===", 13, 10, 0
    msg_header_len  equ $ - msg_header - 1

    msg_ecall       db "ECALL exit... ", 0
    msg_ecall_len   equ $ - msg_ecall - 1

    msg_fence       db "FENCE (NOP)... ", 0
    msg_fence_len   equ $ - msg_fence - 1

    msg_csr         db "CSR stub... ", 0
    msg_csr_len     equ $ - msg_csr - 1

    msg_pass        db "PASS", 13, 10, 0
    msg_pass_len    equ $ - msg_pass - 1

    msg_fail        db "FAIL", 13, 10, 0
    msg_fail_len    equ $ - msg_fail - 1

    ; Test 1: ECALL exit
    ; li a0, 42        ; exit code
    ; li a7, 93        ; exit syscall
    ; ecall
    align 4
    test_ecall:
        dd 0x02A00513       ; addi a0, x0, 42    (x10 = 42)
        dd 0x05D00893       ; addi a7, x0, 93    (x17 = 93 = exit)
        dd 0x00000073       ; ecall

    ; Test 2: FENCE (should be a NOP)
    ; li x1, 10
    ; fence
    ; li x2, 20
    ; beq x0, x0, 0    ; loop
    align 4
    test_fence:
        dd 0x00A00093       ; addi x1, x0, 10
        dd 0x0FF0000F       ; fence iorw, iorw
        dd 0x01400113       ; addi x2, x0, 20
        dd 0x00000063       ; beq x0, x0, 0 (loop)

    ; Test 3: CSR read (should return 0 for our stub)
    ; csrrs x1, cycle, x0   ; read cycle CSR into x1
    ; li x2, 0              ; expected value
    ; beq x0, x0, 0         ; loop
    ; Note: The CSR will return 0 because we're a teapot, not a kettle
    align 4
    test_csr:
        dd 0xC00020F3       ; csrrs x1, cycle, x0  (read CSR 0xC00 into x1)
        dd 0x00000113       ; addi x2, x0, 0
        dd 0x00000063       ; beq x0, x0, 0

    tests_passed    dq 0
    stdout_handle   dq 0

section .bss
    old_protect     resd 1
    bytes_written   resd 1
    alignb 8
    rv_regs         resq 32
    rv_pc           resq 1

section .text
    global main

main:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rbx
    mov [rbp-16], r12

    ; Get stdout
    mov ecx, -11
    call GetStdHandle
    mov [stdout_handle], rax

    ; Make code buffer executable
    lea rcx, [code_buffer]
    mov rdx, 1048576
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    ; Print header
    lea rcx, [msg_header]
    mov edx, msg_header_len
    call print_string

    call init_block_cache

    ;==========================================================================
    ; Test 1: ECALL exit
    ;==========================================================================
    lea rcx, [msg_ecall]
    mov edx, msg_ecall_len
    call print_string

    ; Clear registers
    call clear_regs

    ; Execute
    xor edi, edi
    lea rsi, [test_ecall]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8, 10
    call execute_blocks

    ; Check a0 = 42 (exit code should be preserved)
    lea rbx, [rv_regs]
    cmp qword [rbx + 10*8], 42
    jne .ecall_fail

    ; Check a7 = 93 (syscall number should be preserved)
    cmp qword [rbx + 17*8], 93
    jne .ecall_fail

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .test_fence

.ecall_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.test_fence:
    ;==========================================================================
    ; Test 2: FENCE
    ;==========================================================================
    lea rcx, [msg_fence]
    mov edx, msg_fence_len
    call print_string

    call init_block_cache
    call clear_regs

    xor edi, edi
    lea rsi, [test_fence]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8, 2
    call execute_blocks

    ; Check x1 = 10, x2 = 20
    lea rbx, [rv_regs]
    cmp qword [rbx + 1*8], 10
    jne .fence_fail
    cmp qword [rbx + 2*8], 20
    jne .fence_fail

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .test_csr

.fence_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.test_csr:
    ;==========================================================================
    ; Test 3: CSR (stub returns 0)
    ;==========================================================================
    lea rcx, [msg_csr]
    mov edx, msg_csr_len
    call print_string

    call init_block_cache
    call clear_regs

    ; Set x1 to non-zero to verify CSR overwrites it
    lea rbx, [rv_regs]
    mov qword [rbx + 1*8], 999

    xor edi, edi
    lea rsi, [test_csr]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8, 2
    call execute_blocks

    ; Check x1 = 0 (CSR stub returns 0)
    lea rbx, [rv_regs]
    cmp qword [rbx + 1*8], 0
    jne .csr_fail

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .summary

.csr_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.summary:
    ; Exit with number of tests passed (should be 3)
    mov ecx, [tests_passed]
    call ExitProcess

clear_regs:
    lea rdi, [rv_regs]
    mov rcx, 32
    xor eax, eax
.clear:
    mov [rdi], rax
    add rdi, 8
    dec rcx
    jnz .clear
    ret

print_string:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov r8, rcx
    mov r9d, edx
    mov rcx, [stdout_handle]
    mov rdx, r8
    mov r8d, r9d
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteConsoleA
    leave
    ret
