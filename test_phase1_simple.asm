; test_phase1_simple.asm
; Conway Phase 1 Tests - Self-contained version
; "Have you tried turning it off and on again?"

bits 64
default rel

PAGE_EXECUTE_READWRITE equ 0x40

; RISC-V opcodes
RV_OP_LUI       equ 0x37
RV_OP_AUIPC     equ 0x17
RV_OP_OP_IMM    equ 0x13
RV_OP_OP        equ 0x33

RV_F3_ADDI      equ 0x0
RV_F3_SLTI      equ 0x2
RV_F3_SLTIU     equ 0x3
RV_F3_XORI      equ 0x4
RV_F3_ORI       equ 0x6
RV_F3_ANDI      equ 0x7
RV_F3_SLLI      equ 0x1
RV_F3_SRLI_SRAI equ 0x5

RV_F3_ADD_SUB   equ 0x0
RV_F3_SLL       equ 0x1
RV_F3_SLT       equ 0x2
RV_F3_SLTU      equ 0x3
RV_F3_XOR       equ 0x4
RV_F3_SRL_SRA   equ 0x5
RV_F3_OR        equ 0x6
RV_F3_AND       equ 0x7

RV_F7_NORMAL    equ 0x00
RV_F7_ALT       equ 0x20

section .data
    ; Test instructions
    tests:
        ; Each entry: instruction (dd), register to check (db), padding (db), expected value (dq), name pointer (dq)
        ; Test 1: addi a0, zero, 42  =>  a0 = 42
        dd 0x02a00513
        db 10, 0, 0, 0
        dq 42
        dq name_addi

        ; Test 2: lui a0, 0x12345  =>  a0 = 0x12345000
        dd 0x12345537
        db 10, 0, 0, 0
        dq 0x12345000
        dq name_lui

        ; Test 3: addi t0, zero, 100  =>  t0 = 100
        dd 0x06400293
        db 5, 0, 0, 0
        dq 100
        dq name_addi_t0

        ; Test 4: addi t1, zero, -50  =>  t1 = -50
        dd 0xFCE00313
        db 6, 0, 0, 0
        dq -50
        dq name_addi_neg

        ; Test 5: xori a0, zero, 0x55  =>  a0 = 0x55
        dd 0x05504513
        db 10, 0, 0, 0
        dq 0x55
        dq name_xori

        ; Test 6: ori a0, zero, 0xAB  =>  a0 = 0xAB
        dd 0x0AB06513
        db 10, 0, 0, 0
        dq 0xAB
        dq name_ori

        ; Test 7: andi a0, zero, 0xFF  =>  a0 = 0 (0 AND x = 0)
        dd 0x0FF07513
        db 10, 0, 0, 0
        dq 0
        dq name_andi

        ; Test 8: slli a0, zero, 5  =>  a0 = 0
        dd 0x00501513
        db 10, 0, 0, 0
        dq 0
        dq name_slli_zero

        ; Test 9: slti a0, zero, 1  =>  a0 = 1 (0 < 1)
        dd 0x00102513
        db 10, 0, 0, 0
        dq 1
        dq name_slti

        ; Test 10: sltiu a0, zero, 1  =>  a0 = 1 (0 < 1 unsigned)
        dd 0x00103513
        db 10, 0, 0, 0
        dq 1
        dq name_sltiu

    tests_end:

    num_tests equ (tests_end - tests) / 24

    ; Test names
    name_addi:      db "addi a0, zero, 42 = 42", 0
    name_lui:       db "lui a0, 0x12345 = 0x12345000", 0
    name_addi_t0:   db "addi t0, zero, 100 = 100", 0
    name_addi_neg:  db "addi t1, zero, -50 = -50", 0
    name_xori:      db "xori a0, zero, 0x55 = 0x55", 0
    name_ori:       db "ori a0, zero, 0xAB = 0xAB", 0
    name_andi:      db "andi a0, zero, 0xFF = 0", 0
    name_slli_zero: db "slli a0, zero, 5 = 0", 0
    name_slti:      db "slti a0, zero, 1 = 1", 0
    name_sltiu:     db "sltiu a0, zero, 1 = 1", 0

    fmt_test:       db "[%02d] %s", 10, 0
    fmt_pass:       db "     PASS", 10, 0
    fmt_fail:       db "     FAIL: expected %lld, got %lld", 10, 0
    fmt_summary:    db 10, "========================================", 10
                    db "Phase 1 Results: %d/%d tests passed", 10
                    db "========================================", 10, 0

section .bss
    alignb 16
    code_buffer: resb 4096

    alignb 8
    rv_regs: resq 32
    rv_pc: resq 1

    old_protect: resd 1

section .text
    global main
    extern printf
    extern VirtualProtect
    extern ExitProcess

main:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Make buffer executable
    lea rcx, [code_buffer]
    mov rdx, 4096
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    ; r12 = current test pointer
    ; r13 = test number
    ; r14 = passed count
    ; r15 = total count
    lea r12, [tests]
    xor r13d, r13d
    xor r14d, r14d
    mov r15d, num_tests

.test_loop:
    cmp r13d, r15d
    jge .done

    ; Print test name
    inc r13d
    lea rcx, [fmt_test]
    mov edx, r13d
    mov r8, [r12 + 16]          ; name pointer
    call printf

    ; Reset register file
    call reset_state

    ; Get instruction
    mov edi, [r12]

    ; Translate and run
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

    ; Check result
    movzx eax, byte [r12 + 4]   ; register number
    shl eax, 3
    lea rcx, [rv_regs]
    mov rax, [rcx + rax]        ; actual value

    mov rdx, [r12 + 8]          ; expected value

    cmp rax, rdx
    jne .fail

    ; Pass
    inc r14d
    lea rcx, [fmt_pass]
    call printf
    jmp .next

.fail:
    lea rcx, [fmt_fail]
    mov r8, rax                 ; actual
    ; rdx already has expected
    call printf

.next:
    add r12, 24                 ; next test entry
    jmp .test_loop

.done:
    ; Print summary
    lea rcx, [fmt_summary]
    mov edx, r14d
    mov r8d, r15d
    call printf

    ; Exit with failure count
    mov ecx, r15d
    sub ecx, r14d

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    add rsp, 64
    pop rbp
    call ExitProcess

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
; Inline translate_instruction (copy from main file)
;==============================================================================
translate_instruction:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rsi
    mov r13d, edi
    lea r14, [code_buffer]

    mov eax, edi
    and eax, 0x7F

    cmp eax, RV_OP_LUI
    je .lui
    cmp eax, RV_OP_AUIPC
    je .auipc
    cmp eax, RV_OP_OP_IMM
    je .op_imm
    cmp eax, RV_OP_OP
    je .op_reg

    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

.lui:
    call extract_u_type
    test ecx, ecx
    jz .emit_nop
    mov byte [r12], 0x48
    mov byte [r12+1], 0xB8
    cdqe
    mov [r12+2], rax
    mov byte [r12+10], 0x48
    mov byte [r12+11], 0x89
    mov byte [r12+12], 0x43
    mov eax, ecx
    shl eax, 3
    mov [r12+13], al
    mov rax, 14
    jmp .done

.auipc:
    call extract_u_type
    test ecx, ecx
    jz .emit_nop
    mov byte [r12], 0x48
    mov byte [r12+1], 0xB8
    cdqe
    mov [r12+2], rax
    mov byte [r12+10], 0x48
    mov byte [r12+11], 0x89
    mov byte [r12+12], 0x43
    mov eax, ecx
    shl eax, 3
    mov [r12+13], al
    mov rax, 14
    jmp .done

.op_imm:
    mov eax, r13d
    shr eax, 12
    and eax, 0x7

    cmp eax, RV_F3_ADDI
    je .addi
    cmp eax, RV_F3_SLTI
    je .slti
    cmp eax, RV_F3_SLTIU
    je .sltiu
    cmp eax, RV_F3_XORI
    je .xori
    cmp eax, RV_F3_ORI
    je .ori
    cmp eax, RV_F3_ANDI
    je .andi
    cmp eax, RV_F3_SLLI
    je .slli
    cmp eax, RV_F3_SRLI_SRAI
    je .srli_srai

    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

.addi:
    call extract_i_type
    test ecx, ecx
    jz .emit_nop
    test ebx, ebx
    jz .emit_li
    call emit_load_rs1
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], eax
    add r12, 6
    call emit_store_rd
    jmp .calc_size

.emit_li:
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC0
    mov [r12+3], eax
    add r12, 7
    call emit_store_rd
    jmp .calc_size

.slti:
    call extract_i_type
    test ecx, ecx
    jz .emit_nop
    call emit_load_rs1
    mov byte [r12], 0x48
    mov byte [r12+1], 0x3D
    mov [r12+2], eax
    add r12, 6
    mov byte [r12], 0x0F
    mov byte [r12+1], 0x9C
    mov byte [r12+2], 0xC0
    add r12, 3
    mov byte [r12], 0x48
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB6
    mov byte [r12+3], 0xC0
    add r12, 4
    call emit_store_rd
    jmp .calc_size

.sltiu:
    call extract_i_type
    test ecx, ecx
    jz .emit_nop
    call emit_load_rs1
    mov byte [r12], 0x48
    mov byte [r12+1], 0x3D
    mov [r12+2], eax
    add r12, 6
    mov byte [r12], 0x0F
    mov byte [r12+1], 0x92
    mov byte [r12+2], 0xC0
    add r12, 3
    mov byte [r12], 0x48
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB6
    mov byte [r12+3], 0xC0
    add r12, 4
    call emit_store_rd
    jmp .calc_size

.xori:
    call extract_i_type
    test ecx, ecx
    jz .emit_nop
    test ebx, ebx
    jnz .xori_general
    jmp .emit_li
.xori_general:
    call emit_load_rs1
    mov byte [r12], 0x48
    mov byte [r12+1], 0x35
    mov [r12+2], eax
    add r12, 6
    call emit_store_rd
    jmp .calc_size

.ori:
    call extract_i_type
    test ecx, ecx
    jz .emit_nop
    test ebx, ebx
    jnz .ori_general
    jmp .emit_li
.ori_general:
    call emit_load_rs1
    mov byte [r12], 0x48
    mov byte [r12+1], 0x0D
    mov [r12+2], eax
    add r12, 6
    call emit_store_rd
    jmp .calc_size

.andi:
    call extract_i_type
    test ecx, ecx
    jz .emit_nop
    test ebx, ebx
    jnz .andi_general
    xor eax, eax
    jmp .emit_li
.andi_general:
    call emit_load_rs1
    mov byte [r12], 0x48
    mov byte [r12+1], 0x25
    mov [r12+2], eax
    add r12, 6
    call emit_store_rd
    jmp .calc_size

.slli:
    call extract_i_type
    and eax, 0x3F
    test ecx, ecx
    jz .emit_nop
    test ebx, ebx
    jnz .slli_general
    xor eax, eax
    jmp .emit_li
.slli_general:
    push rax
    call emit_load_rs1
    pop rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC1
    mov byte [r12+2], 0xE0
    mov [r12+3], cl
    add r12, 4
    mov ecx, r15d
    call emit_store_rd
    jmp .calc_size

.srli_srai:
    call extract_i_type
    mov r15d, r13d
    shr r15d, 30
    and r15d, 1
    and eax, 0x3F
    test ecx, ecx
    jz .emit_nop
    test ebx, ebx
    jnz .srxi_general
    xor eax, eax
    jmp .emit_li
.srxi_general:
    push rax
    push r15
    call emit_load_rs1
    pop r15
    pop rcx
    test r15d, r15d
    jnz .emit_sra_imm
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC1
    mov byte [r12+2], 0xE8
    mov [r12+3], cl
    add r12, 4
    jmp .srxi_store
.emit_sra_imm:
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC1
    mov byte [r12+2], 0xF8
    mov [r12+3], cl
    add r12, 4
.srxi_store:
    mov eax, r13d
    shr eax, 7
    and eax, 0x1F
    mov ecx, eax
    call emit_store_rd
    jmp .calc_size

.op_reg:
    mov eax, r13d
    shr eax, 12
    and eax, 0x7
    mov r15d, r13d
    shr r15d, 25
    and r15d, 0x7F

    cmp eax, RV_F3_ADD_SUB
    je .add_sub
    cmp eax, RV_F3_XOR
    je .xor_reg
    cmp eax, RV_F3_OR
    je .or_reg
    cmp eax, RV_F3_AND
    je .and_reg

    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

.add_sub:
    call extract_r_type
    test ecx, ecx
    jz .emit_nop
    push rax
    call emit_load_rs1
    pop rax
    push rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov edx, eax
    shl edx, 3
    mov [r12+3], dl
    add r12, 4
    cmp r15d, RV_F7_ALT
    je .emit_sub
    mov byte [r12], 0x48
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xC8
    add r12, 3
    jmp .add_sub_store
.emit_sub:
    mov byte [r12], 0x48
    mov byte [r12+1], 0x29
    mov byte [r12+2], 0xC8
    add r12, 3
.add_sub_store:
    pop rcx
    call emit_store_rd
    jmp .calc_size

.xor_reg:
.or_reg:
.and_reg:
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

.emit_nop:
    mov byte [r12], 0x90
    mov rax, 1
    jmp .done

.calc_size:
    mov rax, r12
    sub rax, r14

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

emit_load_rs1:
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov [r12+3], al
    add r12, 4
    ret

emit_store_rd:
    mov r15d, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x43
    mov eax, ecx
    shl eax, 3
    mov [r12+3], al
    add r12, 4
    ret

extract_i_type:
    mov eax, r13d
    shr eax, 7
    and eax, 0x1F
    mov ecx, eax
    mov eax, r13d
    shr eax, 15
    and eax, 0x1F
    mov ebx, eax
    mov eax, r13d
    sar eax, 20
    ret

extract_r_type:
    mov eax, r13d
    shr eax, 7
    and eax, 0x1F
    mov ecx, eax
    mov eax, r13d
    shr eax, 15
    and eax, 0x1F
    mov ebx, eax
    mov eax, r13d
    shr eax, 20
    and eax, 0x1F
    ret

extract_u_type:
    mov eax, r13d
    shr eax, 7
    and eax, 0x1F
    mov ecx, eax
    mov eax, r13d
    and eax, 0xFFFFF000
    ret
