; test_blocks.asm - Block Cache Tests
; Tests the new translate_block functionality
; "A basic block a day keeps the interpreter away"

bits 64
default rel

extern init_block_cache
extern translate_block
extern lookup_block
extern block_cache
extern code_buffer
extern ExitProcess
extern GetStdHandle
extern WriteConsoleA
extern VirtualProtect

PAGE_EXECUTE_READWRITE equ 0x40

; Block entry offsets (must match translator.asm)
BLOCK_VALID         equ 0
BLOCK_START_PC      equ 8
BLOCK_CODE_PTR      equ 16
BLOCK_CODE_SIZE     equ 24
BLOCK_EXIT_TYPE     equ 28
BLOCK_NEXT_PC       equ 32
BLOCK_TAKEN_PC      equ 40
BLOCK_NOT_TAKEN_PC  equ 48

EXIT_JUMP           equ 1
EXIT_BRANCH         equ 2

section .data
    msg_header      db "=== Block Cache Tests ===", 13, 10, 0
    msg_header_len  equ $ - msg_header - 1

    msg_init        db "Init cache... ", 0
    msg_init_len    equ $ - msg_init - 1

    msg_trans       db "Translate block... ", 0
    msg_trans_len   equ $ - msg_trans - 1

    msg_lookup      db "Lookup cached... ", 0
    msg_lookup_len  equ $ - msg_lookup - 1

    msg_exec        db "Execute block... ", 0
    msg_exec_len    equ $ - msg_exec - 1

    msg_verify      db "Verify results... ", 0
    msg_verify_len  equ $ - msg_verify - 1

    msg_pass        db "PASS", 13, 10, 0
    msg_pass_len    equ $ - msg_pass - 1

    msg_fail        db "FAIL", 13, 10, 0
    msg_fail_len    equ $ - msg_fail - 1

    msg_summary     db 13, 10, "Tests passed: ", 0
    msg_summary_len equ $ - msg_summary - 1

    msg_slash       db "/5", 13, 10, 0
    msg_slash_len   equ $ - msg_slash - 1

    ; Test program: 3 instructions ending in a branch
    ; PC=0:  addi x1, x0, 10     ; x1 = 10
    ; PC=4:  addi x2, x0, 20     ; x2 = 20
    ; PC=8:  add  x3, x1, x2     ; x3 = 30
    ; PC=12: beq  x0, x0, 8      ; always branch (to PC+8 = 20)
    ;
    ; Encodings:
    ; addi x1, x0, 10  = 0x00A00093
    ; addi x2, x0, 20  = 0x01400113
    ; add  x3, x1, x2  = 0x002081B3
    ; beq  x0, x0, 8   = 0x00000463
    ;
    ; Expected: block ends at PC=12 (beq)
    ; taken_pc = 12 + 8 = 20
    ; not_taken_pc = 12 + 4 = 16
    align 4
    test_program:
        dd 0x00A00093       ; PC=0:  addi x1, x0, 10
        dd 0x01400113       ; PC=4:  addi x2, x0, 20
        dd 0x002081B3       ; PC=8:  add  x3, x1, x2
        dd 0x00000463       ; PC=12: beq  x0, x0, 8

    tests_passed    dq 0
    stdout_handle   dq 0

section .bss
    old_protect     resd 1
    bytes_written   resd 1

    ; RISC-V state
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
    mov [rbp-24], r14
    mov [rbp-32], r15

    ; Get stdout
    mov ecx, -11
    call GetStdHandle
    mov [stdout_handle], rax

    ; Make code buffer executable
    lea rcx, [code_buffer]
    mov rdx, 1048576            ; 1MB
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    ; Print header
    lea rcx, [msg_header]
    mov edx, msg_header_len
    call print_string

    ; ===== Test 1: Init cache =====
    lea rcx, [msg_init]
    mov edx, msg_init_len
    call print_string

    call init_block_cache

    ; Verify cache is zeroed (spot check first entry)
    lea rax, [block_cache]
    cmp byte [rax + BLOCK_VALID], 0
    jne .init_fail

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .test_translate

.init_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.test_translate:
    ; ===== Test 2: Translate a block =====
    lea rcx, [msg_trans]
    mov edx, msg_trans_len
    call print_string

    ; Clear registers
    lea rdi, [rv_regs]
    mov rcx, 32
    xor eax, eax
.clear_regs:
    mov [rdi], rax
    add rdi, 8
    dec rcx
    jnz .clear_regs

    ; translate_block(pc=0, guest_mem=test_program)
    xor edi, edi                ; PC = 0
    lea rsi, [test_program]     ; guest memory
    call translate_block

    ; Check we got a valid block back
    test rax, rax
    jz .translate_fail

    ; Check exit type is EXIT_BRANCH (beq at end)
    cmp dword [rax + BLOCK_EXIT_TYPE], EXIT_BRANCH
    jne .translate_fail

    ; Check taken target is 20 (PC=12 + offset=8)
    cmp qword [rax + BLOCK_TAKEN_PC], 20
    jne .translate_fail

    ; Check not-taken target is 16 (PC=12 + 4)
    cmp qword [rax + BLOCK_NOT_TAKEN_PC], 16
    jne .translate_fail

    mov [rbp-40], rax           ; Save block pointer

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .test_lookup

.translate_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.test_lookup:
    ; ===== Test 3: Lookup cached block =====
    lea rcx, [msg_lookup]
    mov edx, msg_lookup_len
    call print_string

    xor edi, edi                ; PC = 0
    call lookup_block

    ; Should find the same block
    cmp rax, [rbp-40]
    jne .lookup_fail

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .test_exec

.lookup_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.test_exec:
    ; ===== Test 4: Execute the block =====
    lea rcx, [msg_exec]
    mov edx, msg_exec_len
    call print_string

    ; Set up RISC-V state pointers
    lea rbx, [rv_regs]
    lea r15, [rv_pc]
    mov qword [rv_pc], 0

    ; Get code pointer from block
    mov rax, [rbp-40]
    mov rax, [rax + BLOCK_CODE_PTR]

    ; Execute!
    call rax

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .test_verify

.exec_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.test_verify:
    ; ===== Test 5: Verify register results =====
    lea rcx, [msg_verify]
    mov edx, msg_verify_len
    call print_string

    lea rbx, [rv_regs]

    ; x1 should be 10
    cmp qword [rbx + 1*8], 10
    jne .verify_fail

    ; x2 should be 20
    cmp qword [rbx + 2*8], 20
    jne .verify_fail

    ; x3 should be 30
    cmp qword [rbx + 3*8], 30
    jne .verify_fail

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .summary

.verify_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.summary:
    lea rcx, [msg_summary]
    mov edx, msg_summary_len
    call print_string

    ; Print count
    mov rax, [tests_passed]
    add al, '0'
    push rax
    mov rcx, rsp
    mov edx, 1
    call print_string
    add rsp, 8

    lea rcx, [msg_slash]
    mov edx, msg_slash_len
    call print_string

    ; Exit code
    mov rax, [tests_passed]
    cmp rax, 5
    je .exit_success
    mov ecx, 1
    jmp .exit
.exit_success:
    xor ecx, ecx
.exit:
    call ExitProcess

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
