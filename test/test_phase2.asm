; test_phase2.asm
; Conway Phase 2 Test Suite - Memory Operations
; "Memory is just spicy storage" - A wise person, probably
;
; Tests all load/store operations

bits 64
default rel

PAGE_EXECUTE_READWRITE equ 0x40

section .data
    ; ===== Store Tests (need to run first to populate memory) =====
    ; li t0, 100        =>  addi t0, zero, 100
    test_li_t0_100:     dd 0x06400293

    ; li t1, 0x1234     =>  addi t1, zero, 0x1234 (but that's >12 bits, need lui)
    ; Actually let's use smaller values
    ; li t1, 0x5A       =>  addi t1, zero, 90
    test_li_t1_90:      dd 0x05A00313

    ; ===== SD - Store Doubleword =====
    ; sd t1, 0(t0)      =>  mem[100] = 90
    ; S-type: imm[11:5]=0 | rs2=t1(6) | rs1=t0(5) | funct3=3 | imm[4:0]=0 | opcode=0x23
    ; = 0000000 | 00110 | 00101 | 011 | 00000 | 0100011
    ; = 0x0062B023
    test_sd:            dd 0x0062B023

    ; ===== SW - Store Word =====
    ; sw t1, 8(t0)      =>  mem[108] = 90
    ; imm = 8 = 0b001000
    ; = 0000000 | 00110 | 00101 | 010 | 01000 | 0100011
    ; = 0x0062A423
    test_sw:            dd 0x0062A423

    ; ===== SH - Store Halfword =====
    ; sh t1, 16(t0)     =>  mem[116] = 90
    ; imm = 16 = 0b010000
    ; = 0000000 | 00110 | 00101 | 001 | 10000 | 0100011
    ; = 0x00629823
    test_sh:            dd 0x00629823

    ; ===== SB - Store Byte =====
    ; sb t1, 24(t0)     =>  mem[124] = 90
    ; imm = 24 = 0b011000
    ; = 0000000 | 00110 | 00101 | 000 | 11000 | 0100011
    ; = 0x00628C23
    test_sb:            dd 0x00628C23

    ; ===== Load Tests =====
    ; ld a0, 0(t0)      =>  a0 = mem[100] = 90
    ; I-type: imm[11:0]=0 | rs1=t0(5) | funct3=3 | rd=a0(10) | opcode=0x03
    ; = 000000000000 | 00101 | 011 | 01010 | 0000011
    ; = 0x0002B503
    test_ld:            dd 0x0002B503

    ; lw a0, 8(t0)      =>  a0 = mem[108] = 90
    ; imm = 8
    ; = 000000001000 | 00101 | 010 | 01010 | 0000011
    ; = 0x0082A503
    test_lw:            dd 0x0082A503

    ; lh a0, 16(t0)     =>  a0 = mem[116] = 90
    ; imm = 16
    ; = 000000010000 | 00101 | 001 | 01010 | 0000011
    ; = 0x01029503
    test_lh:            dd 0x01029503

    ; lb a0, 24(t0)     =>  a0 = mem[124] = 90
    ; imm = 24
    ; = 000000011000 | 00101 | 000 | 01010 | 0000011
    ; = 0x01828503
    test_lb:            dd 0x01828503

    ; ===== Unsigned Load Tests =====
    ; First store 0xFF to test sign extension
    ; li t1, 0xFF
    test_li_t1_ff:      dd 0x0FF00313

    ; sb t1, 32(t0)     =>  mem[132] = 0xFF
    ; imm = 32 = 0b100000 = imm[11:5]=1, imm[4:0]=0
    ; = 0000001 | 00110 | 00101 | 000 | 00000 | 0100011
    ; = 0x02628023
    test_sb_ff:         dd 0x02628023

    ; lb a0, 32(t0)     =>  a0 = signext(0xFF) = -1 = 0xFFFFFFFFFFFFFFFF
    ; imm = 32
    test_lb_signed:     dd 0x02028503

    ; lbu a0, 32(t0)    =>  a0 = zeroext(0xFF) = 255
    ; funct3 = 4 for LBU
    ; = 000000100000 | 00101 | 100 | 01010 | 0000011
    ; = 0x0202C503
    test_lbu:           dd 0x0202C503

    ; Output messages
    fmt_test:   db "Test: %s", 10, 0
    fmt_pass:   db "  PASS: got %lld", 10, 0
    fmt_fail:   db "  FAIL: expected %lld, got %lld", 10, 0
    fmt_done:   db 10, "Phase 2 complete: %d/%d tests passed", 10, 0

    ; Test names
    name_sd:        db "sd t1, 0(t0) then ld", 0
    name_sw:        db "sw t1, 8(t0) then lw", 0
    name_sh:        db "sh t1, 16(t0) then lh", 0
    name_sb:        db "sb t1, 24(t0) then lb", 0
    name_lb_sign:   db "lb sign extension (0xFF -> -1)", 0
    name_lbu:       db "lbu zero extension (0xFF -> 255)", 0

section .bss
    alignb 16
    code_buffer: resb 4096

    alignb 8
    rv_regs: resq 32
    rv_pc: resq 1

    alignb 4096
    rv_memory: resb 65536

    old_protect: resd 1

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
    ; Need to save 5 regs (40 bytes) + 32 shadow space = 72, round up to 80 for alignment
    sub rsp, 80
    mov [rbp-8], rbx
    mov [rbp-16], r12
    mov [rbp-24], r13
    mov [rbp-32], r14
    mov [rbp-40], r15

    ; Initialise test counters
    mov dword [tests_run], 0
    mov dword [tests_passed], 0

    ; Make code buffer executable
    lea rcx, [code_buffer]
    mov rdx, 4096
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    ;--------------------------------------------------
    ; Setup: load t0=100 and t1=90
    ;--------------------------------------------------
    call reset_state
    mov edi, [test_li_t0_100]
    call run_single_instruction
    mov edi, [test_li_t1_90]
    call run_single_instruction

    ;--------------------------------------------------
    ; Test 1: SD then LD
    ;--------------------------------------------------
    lea rcx, [name_sd]
    call print_test_name

    mov edi, [test_sd]          ; Store 90 at address 100
    call run_single_instruction
    mov edi, [test_ld]          ; Load from address 100
    call run_single_instruction

    mov rcx, 10                 ; Check a0
    mov rdx, 90                 ; Expected value
    call check_register

    ;--------------------------------------------------
    ; Test 2: SW then LW
    ;--------------------------------------------------
    lea rcx, [name_sw]
    call print_test_name

    mov edi, [test_sw]          ; Store 90 at address 108
    call run_single_instruction
    mov edi, [test_lw]          ; Load from address 108
    call run_single_instruction

    mov rcx, 10
    mov rdx, 90
    call check_register

    ;--------------------------------------------------
    ; Test 3: SH then LH
    ;--------------------------------------------------
    lea rcx, [name_sh]
    call print_test_name

    mov edi, [test_sh]          ; Store 90 at address 116
    call run_single_instruction
    mov edi, [test_lh]          ; Load from address 116
    call run_single_instruction

    mov rcx, 10
    mov rdx, 90
    call check_register

    ;--------------------------------------------------
    ; Test 4: SB then LB
    ;--------------------------------------------------
    lea rcx, [name_sb]
    call print_test_name

    mov edi, [test_sb]          ; Store 90 at address 124
    call run_single_instruction
    mov edi, [test_lb]          ; Load from address 124
    call run_single_instruction

    mov rcx, 10
    mov rdx, 90
    call check_register

    ;--------------------------------------------------
    ; Test 5: LB sign extension (0xFF -> -1)
    ;--------------------------------------------------
    lea rcx, [name_lb_sign]
    call print_test_name

    ; Load 0xFF into t1
    mov edi, [test_li_t1_ff]
    call run_single_instruction

    ; Store byte 0xFF at address 132
    mov edi, [test_sb_ff]
    call run_single_instruction

    ; Load it back with sign extension
    mov edi, [test_lb_signed]
    call run_single_instruction

    mov rcx, 10
    mov rdx, -1                 ; 0xFF sign-extended = -1
    call check_register

    ;--------------------------------------------------
    ; Test 6: LBU zero extension (0xFF -> 255)
    ;--------------------------------------------------
    lea rcx, [name_lbu]
    call print_test_name

    mov edi, [test_lbu]         ; Load unsigned byte
    call run_single_instruction

    mov rcx, 10
    mov rdx, 255                ; 0xFF zero-extended = 255
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
    call ExitProcess

;==============================================================================
; print_test_name
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
; reset_state
;==============================================================================
reset_state:
    push rdi
    push rcx
    push rax

    ; Clear register file
    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 256
.loop:
    mov [rdi], al
    inc rdi
    dec ecx
    jnz .loop

    ; Clear memory (first 256 bytes is enough for tests)
    lea rdi, [rv_memory]
    xor eax, eax
    mov ecx, 256
.loop2:
    mov [rdi], al
    inc rdi
    dec ecx
    jnz .loop2

    pop rax
    pop rcx
    pop rdi
    ret

;==============================================================================
; run_single_instruction
;==============================================================================
run_single_instruction:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rbx
    mov [rbp-16], r12
    mov [rbp-24], r14
    mov [rbp-32], rdi          ; Save instruction

    mov edi, [rbp-32]          ; Restore instruction to edi

    ; Translate
    lea rsi, [code_buffer]
    call translate_instruction

    ; Append RET
    lea rdi, [code_buffer]
    add rdi, rax
    mov byte [rdi], 0xC3

    ; Execute with RBX = register file, R14 = guest memory
    lea rbx, [rv_regs]
    lea r14, [rv_memory]
    lea rax, [code_buffer]
    call rax

    mov rbx, [rbp-8]
    mov r12, [rbp-16]
    mov r14, [rbp-24]
    add rsp, 64
    pop rbp
    ret

;==============================================================================
; check_register
;==============================================================================
check_register:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    mov [rbp-8], rbx
    mov [rbp-16], rcx          ; Save reg number
    mov [rbp-24], rdx          ; Save expected

    inc dword [tests_run]

    ; Get actual value
    lea rax, [rv_regs]
    mov rbx, [rbp-16]
    shl rbx, 3
    mov rax, [rax + rbx]
    mov [rbp-32], rax          ; Save actual

    mov rdx, [rbp-24]          ; expected
    cmp rax, rdx
    jne .fail

    ; Pass
    inc dword [tests_passed]
    lea rcx, [fmt_pass]
    mov rdx, [rbp-32]
    call printf
    jmp .done

.fail:
    lea rcx, [fmt_fail]
    mov rdx, [rbp-24]          ; expected
    mov r8, [rbp-32]           ; actual
    call printf

.done:
    mov rbx, [rbp-8]
    add rsp, 64
    pop rbp
    ret
