; test_phase3.asm - Phase 3 Control Flow Tests
; Tests JAL, JALR, and conditional branches
; "Have you tried turning it off and on again?"

bits 64
default rel

; External functions from translator
extern translate_instruction

; Windows API
extern ExitProcess
extern GetStdHandle
extern WriteConsoleA
extern VirtualProtect

PAGE_EXECUTE_READWRITE equ 0x40

section .data
    ; Test messages
    test_header     db "=== Phase 3: Control Flow ===", 13, 10, 0
    test_header_len equ $ - test_header - 1

    test_jal        db "Testing JAL... ", 0
    test_jal_len    equ $ - test_jal - 1

    test_jalr       db "Testing JALR... ", 0
    test_jalr_len   equ $ - test_jalr - 1

    test_beq        db "Testing BEQ... ", 0
    test_beq_len    equ $ - test_beq - 1

    test_bne        db "Testing BNE... ", 0
    test_bne_len    equ $ - test_bne - 1

    test_blt        db "Testing BLT... ", 0
    test_blt_len    equ $ - test_blt - 1

    test_bge        db "Testing BGE... ", 0
    test_bge_len    equ $ - test_bge - 1

    msg_pass        db "PASS", 13, 10, 0
    msg_pass_len    equ $ - msg_pass - 1

    msg_fail        db "FAIL", 13, 10, 0
    msg_fail_len    equ $ - msg_fail - 1

    summary_msg     db 13, 10, "Tests passed: ", 0
    summary_msg_len equ $ - summary_msg - 1

    slash_msg       db "/6", 13, 10, 0
    slash_msg_len   equ $ - slash_msg - 1

    ; RISC-V test instructions
    ; JAL x1, 8  (jump forward 8 bytes, save return to x1)
    ; imm = 8 = 0b00000000000000001000
    ; imm[20|10:1|11|19:12] = 0|0000000100|0|00000000 = 0x00800
    ; Full: 0x00800 << 12 | rd=1 << 7 | 0x6F = 0x008000EF
    instr_jal       dd 0x008000EF

    ; JALR x1, x5, 0  (jump to x5+0, save return to x1)
    ; imm[11:0]=0 | rs1=5 | funct3=0 | rd=1 | opcode=0x67
    ; = 0x000280E7
    instr_jalr      dd 0x000280E7

    ; BEQ x5, x6, 16  (branch if x5 == x6, offset 16)
    ; imm=16, rs2=6, rs1=5, funct3=0, opcode=0x63
    ; imm[12|10:5]=0|000000, imm[4:1|11]=1000|0
    ; = 0x00628863
    instr_beq       dd 0x00628863

    ; BNE x5, x6, 16  (funct3=1)
    instr_bne       dd 0x00629863

    ; BLT x5, x6, 16  (funct3=4)
    instr_blt       dd 0x0062C863

    ; BGE x5, x6, 16  (funct3=5)
    instr_bge       dd 0x0062D863

    tests_passed    dq 0
    stdout_handle   dq 0

section .bss
    alignb 16
    code_buffer     resb 4096
    bytes_written   resd 1
    old_protect     resd 1

    ; RISC-V state
    alignb 8
    rv_regs         resq 32         ; 32 registers
    rv_pc           resq 1          ; Programme counter

    alignb 4096
    rv_memory       resb 65536      ; 64KB guest memory

section .text
    global main

;==============================================================================
; translate_and_execute - Translate instruction and run it
; ECX = instruction, returns nothing
; Clobbers most registers but preserves rbx
;==============================================================================
translate_and_execute:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rbx
    mov [rbp-16], r12
    mov [rbp-24], r14
    mov [rbp-32], r15
    mov [rbp-40], ecx               ; Save instruction

    ; Translate: EDI = instruction, RSI = output buffer (System V convention)
    mov edi, ecx
    lea rsi, [code_buffer]
    call translate_instruction      ; Returns bytes written in RAX

    ; Append RET (0xC3) for safe return
    lea rdi, [code_buffer]
    add rdi, rax
    mov byte [rdi], 0xC3

    ; Set up RISC-V state pointers for generated code
    lea rbx, [rv_regs]
    lea r14, [rv_memory]
    lea r15, [rv_pc]

    ; Execute translated code
    lea rax, [code_buffer]
    call rax

    ; Restore
    mov rbx, [rbp-8]
    mov r12, [rbp-16]
    mov r14, [rbp-24]
    mov r15, [rbp-32]
    add rsp, 64
    pop rbp
    ret

;==============================================================================
; main
;==============================================================================
main:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rbx

    ; Get stdout handle
    mov ecx, -11
    call GetStdHandle
    mov [stdout_handle], rax

    ; Make code buffer executable
    lea rcx, [code_buffer]
    mov rdx, 4096
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    ; Print header
    lea rcx, [test_header]
    mov edx, test_header_len
    call print_string

    ; ===== Test 1: JAL =====
    lea rcx, [test_jal]
    mov edx, test_jal_len
    call print_string

    ; Reset state: PC=0, x1=0
    xor eax, eax
    mov [rv_pc], rax
    lea rbx, [rv_regs]
    mov qword [rbx + 1*8], 0

    ; Execute JAL x1, 8
    mov ecx, [instr_jal]
    call translate_and_execute

    ; Check: x1 should be 4 (return address), PC should be 8
    lea rbx, [rv_regs]
    mov rax, [rbx + 1*8]
    cmp rax, 4
    jne .jal_fail
    mov rax, [rv_pc]
    cmp rax, 8
    jne .jal_fail

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .test_jalr

.jal_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.test_jalr:
    ; ===== Test 2: JALR =====
    lea rcx, [test_jalr]
    mov edx, test_jalr_len
    call print_string

    ; Reset: PC=0, x1=0, x5=100
    xor eax, eax
    mov [rv_pc], rax
    lea rbx, [rv_regs]
    mov qword [rbx + 1*8], 0
    mov qword [rbx + 5*8], 100

    ; Execute JALR x1, x5, 0
    mov ecx, [instr_jalr]
    call translate_and_execute

    ; Check: x1=4, PC=100
    lea rbx, [rv_regs]
    mov rax, [rbx + 1*8]
    cmp rax, 4
    jne .jalr_fail
    mov rax, [rv_pc]
    cmp rax, 100
    jne .jalr_fail

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .test_beq

.jalr_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.test_beq:
    ; ===== Test 3: BEQ (taken) =====
    lea rcx, [test_beq]
    mov edx, test_beq_len
    call print_string

    ; PC=0, x5=x6=42 (equal, should branch)
    xor eax, eax
    mov [rv_pc], rax
    lea rbx, [rv_regs]
    mov qword [rbx + 5*8], 42
    mov qword [rbx + 6*8], 42

    mov ecx, [instr_beq]
    call translate_and_execute

    ; PC should be 16 (branch taken)
    mov rax, [rv_pc]
    cmp rax, 16
    jne .beq_fail

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .test_bne

.beq_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.test_bne:
    ; ===== Test 4: BNE (taken) =====
    lea rcx, [test_bne]
    mov edx, test_bne_len
    call print_string

    ; PC=0, x5=10, x6=20 (not equal, should branch)
    xor eax, eax
    mov [rv_pc], rax
    lea rbx, [rv_regs]
    mov qword [rbx + 5*8], 10
    mov qword [rbx + 6*8], 20

    mov ecx, [instr_bne]
    call translate_and_execute

    ; PC should be 16
    mov rax, [rv_pc]
    cmp rax, 16
    jne .bne_fail

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .test_blt

.bne_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.test_blt:
    ; ===== Test 5: BLT (taken) =====
    lea rcx, [test_blt]
    mov edx, test_blt_len
    call print_string

    ; PC=0, x5=-5, x6=10 (signed: -5 < 10, should branch)
    xor eax, eax
    mov [rv_pc], rax
    lea rbx, [rv_regs]
    mov qword [rbx + 5*8], -5
    mov qword [rbx + 6*8], 10

    mov ecx, [instr_blt]
    call translate_and_execute

    ; PC should be 16
    mov rax, [rv_pc]
    cmp rax, 16
    jne .blt_fail

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .test_bge

.blt_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.test_bge:
    ; ===== Test 6: BGE (taken) =====
    lea rcx, [test_bge]
    mov edx, test_bge_len
    call print_string

    ; PC=0, x5=50, x6=50 (equal means >=, should branch)
    xor eax, eax
    mov [rv_pc], rax
    lea rbx, [rv_regs]
    mov qword [rbx + 5*8], 50
    mov qword [rbx + 6*8], 50

    mov ecx, [instr_bge]
    call translate_and_execute

    ; PC should be 16
    mov rax, [rv_pc]
    cmp rax, 16
    jne .bge_fail

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .summary

.bge_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.summary:
    lea rcx, [summary_msg]
    mov edx, summary_msg_len
    call print_string

    ; Print count
    mov rax, [tests_passed]
    add al, '0'
    mov [code_buffer], al
    lea rcx, [code_buffer]
    mov edx, 1
    call print_string

    lea rcx, [slash_msg]
    mov edx, slash_msg_len
    call print_string

    ; Exit code: 0 if 6 passed, 1 otherwise
    mov rax, [tests_passed]
    cmp rax, 6
    je .exit_success
    mov ecx, 1
    jmp .exit
.exit_success:
    xor ecx, ecx
.exit:
    call ExitProcess

;==============================================================================
; print_string - Print to stdout
; RCX = string, EDX = length
;==============================================================================
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
