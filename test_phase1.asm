; test_phase1.asm
; Conway Phase 1 Test Suite
; "0118 999 881 999 119 725... 3" - Emergency number for when tests fail
;
; Tests all arithmetic operations without memory access

bits 64
default rel

PAGE_EXECUTE_READWRITE equ 0x40

section .data
    ; Test case format: instruction, expected_rd, expected_value, description

    ; ===== ADDI Tests =====
    ; addi a0, zero, 42  =>  a0 = 42
    test_addi_li:       dd 0x02a00513

    ; ===== LUI Tests =====
    ; lui a0, 0x12345  =>  a0 = 0x12345000
    test_lui:           dd 0x12345537

    ; ===== ADD/SUB Tests =====
    ; We need to set up registers first, then test
    ; li t0, 10     =>  addi t0, zero, 10
    test_li_t0_10:      dd 0x00a00293
    ; li t1, 7      =>  addi t1, zero, 7
    test_li_t1_7:       dd 0x00700313
    ; add a0, t0, t1  =>  a0 = 10 + 7 = 17
    test_add:           dd 0x006282b3  ; Hmm, this puts result in t0. Let me fix.

    ; Actually let's do: add a0, t0, t1
    ; rd=a0(10), rs1=t0(5), rs2=t1(6)
    ; opcode=0x33, funct3=0, funct7=0
    ; Encoding: 0000000 00110 00101 000 01010 0110011
    ;         = 0x006285b3... wait let me recalculate
    ; Actually: funct7[6:0] rs2[4:0] rs1[4:0] funct3[2:0] rd[4:0] opcode[6:0]
    ; = 0000000 | 00110 | 00101 | 000 | 01010 | 0110011
    ; = 0x00628533
    test_add_proper:    dd 0x00628533

    ; sub a0, t0, t1  =>  a0 = 10 - 7 = 3
    ; funct7=0x20 for SUB
    ; = 0100000 | 00110 | 00101 | 000 | 01010 | 0110011
    ; = 0x40628533
    test_sub:           dd 0x40628533

    ; ===== Bitwise Tests =====
    ; xori a0, t0, 0xFF  =>  a0 = 10 ^ 255 = 245
    test_xori:          dd 0x0FF2C513

    ; ori a0, t0, 0x0F  =>  a0 = 10 | 15 = 15
    test_ori:           dd 0x00F2E513

    ; andi a0, t0, 0x0E  =>  a0 = 10 & 14 = 10
    test_andi:          dd 0x00E2F513

    ; ===== Shift Tests =====
    ; slli a0, t0, 2  =>  a0 = 10 << 2 = 40
    test_slli:          dd 0x00229513

    ; srli a0, t0, 1  =>  a0 = 10 >> 1 = 5
    test_srli:          dd 0x0012D513

    ; ===== Comparison Tests =====
    ; slti a0, t0, 15  =>  a0 = (10 < 15) = 1
    test_slti_true:     dd 0x00F2A513

    ; slti a0, t0, 5   =>  a0 = (10 < 5) = 0
    test_slti_false:    dd 0x0052A513

    ; Output messages
    fmt_test:   db "Test: %s", 10, 0
    fmt_pass:   db "  PASS: got %d", 10, 0
    fmt_fail:   db "  FAIL: expected %d, got %d", 10, 0
    fmt_done:   db 10, "Phase 1 complete: %d/%d tests passed", 10, 0

    ; Test names
    name_addi:      db "addi a0, zero, 42", 0
    name_lui:       db "lui a0, 0x12345", 0
    name_add:       db "add a0, t0, t1 (10+7)", 0
    name_sub:       db "sub a0, t0, t1 (10-7)", 0
    name_xori:      db "xori a0, t0, 0xFF", 0
    name_ori:       db "ori a0, t0, 0x0F", 0
    name_andi:      db "andi a0, t0, 0x0E", 0
    name_slli:      db "slli a0, t0, 2", 0
    name_srli:      db "srli a0, t0, 1", 0
    name_slti_t:    db "slti a0, t0, 15 (true)", 0
    name_slti_f:    db "slti a0, t0, 5 (false)", 0

section .bss
    alignb 16
    code_buffer: resb 4096

    alignb 8
    rv_regs: resq 32
    rv_pc: resq 1

    old_protect: resd 1

    ; Test counters
    tests_run: resd 1
    tests_passed: resd 1

section .text
    global main
    extern printf
    extern VirtualProtect
    extern ExitProcess
    extern translate_instruction

;==============================================================================
; Main test runner
;==============================================================================
main:
    push rbp
    mov rbp, rsp
    sub rsp, 96
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Initialise test counters
    mov dword [tests_run], 0
    mov dword [tests_passed], 0

    ; Make code buffer executable once
    lea rcx, [code_buffer]
    mov rdx, 4096
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    ;--------------------------------------------------
    ; Test 1: addi a0, zero, 42
    ;--------------------------------------------------
    lea rcx, [name_addi]
    call print_test_name

    call reset_state
    mov edi, [test_addi_li]
    call run_single_instruction

    mov rcx, 10                 ; Check a0
    mov rdx, 42                 ; Expected value
    call check_register

    ;--------------------------------------------------
    ; Test 2: lui a0, 0x12345
    ;--------------------------------------------------
    lea rcx, [name_lui]
    call print_test_name

    call reset_state
    mov edi, [test_lui]
    call run_single_instruction

    mov rcx, 10
    mov rdx, 0x12345000
    call check_register

    ;--------------------------------------------------
    ; Setup for register-register tests
    ; Load t0=10, t1=7
    ;--------------------------------------------------
    call reset_state
    mov edi, [test_li_t0_10]
    call run_single_instruction
    mov edi, [test_li_t1_7]
    call run_single_instruction

    ;--------------------------------------------------
    ; Test 3: add a0, t0, t1  =>  17
    ;--------------------------------------------------
    lea rcx, [name_add]
    call print_test_name

    mov edi, [test_add_proper]
    call run_single_instruction

    mov rcx, 10
    mov rdx, 17
    call check_register

    ;--------------------------------------------------
    ; Test 4: sub a0, t0, t1  =>  3
    ;--------------------------------------------------
    lea rcx, [name_sub]
    call print_test_name

    mov edi, [test_sub]
    call run_single_instruction

    mov rcx, 10
    mov rdx, 3
    call check_register

    ;--------------------------------------------------
    ; Test 5: xori a0, t0, 0xFF  =>  245
    ;--------------------------------------------------
    lea rcx, [name_xori]
    call print_test_name

    mov edi, [test_xori]
    call run_single_instruction

    mov rcx, 10
    mov rdx, 245
    call check_register

    ;--------------------------------------------------
    ; Test 6: ori a0, t0, 0x0F  =>  15
    ;--------------------------------------------------
    lea rcx, [name_ori]
    call print_test_name

    mov edi, [test_ori]
    call run_single_instruction

    mov rcx, 10
    mov rdx, 15
    call check_register

    ;--------------------------------------------------
    ; Test 7: andi a0, t0, 0x0E  =>  10
    ;--------------------------------------------------
    lea rcx, [name_andi]
    call print_test_name

    mov edi, [test_andi]
    call run_single_instruction

    mov rcx, 10
    mov rdx, 10
    call check_register

    ;--------------------------------------------------
    ; Test 8: slli a0, t0, 2  =>  40
    ;--------------------------------------------------
    lea rcx, [name_slli]
    call print_test_name

    mov edi, [test_slli]
    call run_single_instruction

    mov rcx, 10
    mov rdx, 40
    call check_register

    ;--------------------------------------------------
    ; Test 9: srli a0, t0, 1  =>  5
    ;--------------------------------------------------
    lea rcx, [name_srli]
    call print_test_name

    mov edi, [test_srli]
    call run_single_instruction

    mov rcx, 10
    mov rdx, 5
    call check_register

    ;--------------------------------------------------
    ; Test 10: slti a0, t0, 15  =>  1 (true)
    ;--------------------------------------------------
    lea rcx, [name_slti_t]
    call print_test_name

    mov edi, [test_slti_true]
    call run_single_instruction

    mov rcx, 10
    mov rdx, 1
    call check_register

    ;--------------------------------------------------
    ; Test 11: slti a0, t0, 5  =>  0 (false)
    ;--------------------------------------------------
    lea rcx, [name_slti_f]
    call print_test_name

    mov edi, [test_slti_false]
    call run_single_instruction

    mov rcx, 10
    mov rdx, 0
    call check_register

    ;--------------------------------------------------
    ; Print summary
    ;--------------------------------------------------
    lea rcx, [fmt_done]
    mov edx, [tests_passed]
    mov r8d, [tests_run]
    call printf

    ; Exit with number of failures
    mov eax, [tests_run]
    sub eax, [tests_passed]
    mov ecx, eax

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    add rsp, 96
    pop rbp
    call ExitProcess

;==============================================================================
; print_test_name - Print test name
; Input: RCX = name string
;==============================================================================
print_test_name:
    push rbp
    mov rbp, rsp
    sub rsp, 32

    mov rdx, rcx
    lea rcx, [fmt_test]
    call printf

    add rsp, 32
    pop rbp
    ret

;==============================================================================
; reset_state - Clear register file
;==============================================================================
reset_state:
    push rdi
    push rcx
    push rax

    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 256
.loop:
    mov [rdi], al
    inc rdi
    dec ecx
    jnz .loop

    pop rax
    pop rcx
    pop rdi
    ret

;==============================================================================
; run_single_instruction
; Input: EDI = RISC-V instruction
;==============================================================================
run_single_instruction:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    push rbx
    push r12

    ; Translate
    lea rsi, [code_buffer]
    call translate_instruction

    ; Append RET
    lea rdi, [code_buffer]
    add rdi, rax
    mov byte [rdi], 0xC3

    ; Execute
    lea rbx, [rv_regs]
    lea rax, [code_buffer]
    call rax

    pop r12
    pop rbx
    add rsp, 64
    pop rbp
    ret

;==============================================================================
; check_register
; Input: RCX = register number, RDX = expected value
;==============================================================================
check_register:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    push rbx

    inc dword [tests_run]

    ; Get actual value
    lea rax, [rv_regs]
    mov rbx, rcx
    shl rbx, 3
    mov rax, [rax + rbx]

    cmp rax, rdx
    jne .fail

    ; Pass
    inc dword [tests_passed]
    lea rcx, [fmt_pass]
    mov rdx, rax
    call printf
    jmp .done

.fail:
    ; Fail - print expected and actual
    push rax                    ; Save actual
    lea rcx, [fmt_fail]
    ; rdx already has expected
    mov r8, rax                 ; actual
    call printf
    pop rax

.done:
    pop rbx
    add rsp, 48
    pop rbp
    ret
