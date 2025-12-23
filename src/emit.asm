; Conway - RISC-V to x86-64 Binary Translator
; emit.asm - x86-64 code emitter
;
; Generates native x86-64 machine code from decoded RISC-V instructions

%include "x86_opcodes.inc"

section .data

section .bss

section .text
    global emit_prologue
    global emit_epilogue
    global emit_add
    global emit_sub
    global emit_and
    global emit_or
    global emit_xor
    global emit_sll
    global emit_srl
    global emit_sra
    global emit_slt
    global emit_sltu
    global emit_addi
    global emit_load
    global emit_store
    global emit_branch
    global emit_jal
    global emit_jalr
    global emit_lui
    global emit_auipc
    global emit_byte
    global emit_word
    global emit_dword
    global emit_qword

    extern code_ptr
    extern rv_regs

; emit_byte - Emit a single byte to the code buffer
; Input: dil = byte to emit
emit_byte:
    push rbp
    mov rbp, rsp
    mov rax, [rel code_ptr]
    mov [rax], dil
    inc qword [rel code_ptr]
    pop rbp
    ret

; emit_word - Emit a 16-bit word
; Input: di = word to emit
emit_word:
    push rbp
    mov rbp, rsp
    mov rax, [rel code_ptr]
    mov [rax], di
    add qword [rel code_ptr], 2
    pop rbp
    ret

; emit_dword - Emit a 32-bit doubleword
; Input: edi = dword to emit
emit_dword:
    push rbp
    mov rbp, rsp
    mov rax, [rel code_ptr]
    mov [rax], edi
    add qword [rel code_ptr], 4
    pop rbp
    ret

; emit_qword - Emit a 64-bit quadword
; Input: rdi = qword to emit
emit_qword:
    push rbp
    mov rbp, rsp
    mov rax, [rel code_ptr]
    mov [rax], rdi
    add qword [rel code_ptr], 8
    pop rbp
    ret

; emit_prologue - Emit function prologue for translated code
emit_prologue:
    push rbp
    mov rbp, rsp

    ; push rbp
    mov dil, 0x55
    call emit_byte

    ; mov rbp, rsp (48 89 E5)
    mov dil, 0x48
    call emit_byte
    mov dil, 0x89
    call emit_byte
    mov dil, 0xE5
    call emit_byte

    ; Save callee-saved registers
    ; push rbx (53)
    mov dil, 0x53
    call emit_byte
    ; push r12 (41 54)
    mov di, 0x5441
    call emit_word
    ; push r13 (41 55)
    mov di, 0x5541
    call emit_word
    ; push r14 (41 56)
    mov di, 0x5641
    call emit_word
    ; push r15 (41 57)
    mov di, 0x5741
    call emit_word

    ; Load RISC-V register base into rbx
    ; mov rbx, imm64 (48 BB + 8 bytes)
    mov dil, 0x48
    call emit_byte
    mov dil, 0xBB
    call emit_byte
    lea rdi, [rel rv_regs]
    call emit_qword

    pop rbp
    ret

; emit_epilogue - Emit function epilogue for translated code
emit_epilogue:
    push rbp
    mov rbp, rsp

    ; Restore callee-saved registers
    ; pop r15 (41 5F)
    mov di, 0x5F41
    call emit_word
    ; pop r14 (41 5E)
    mov di, 0x5E41
    call emit_word
    ; pop r13 (41 5D)
    mov di, 0x5D41
    call emit_word
    ; pop r12 (41 5C)
    mov di, 0x5C41
    call emit_word
    ; pop rbx (5B)
    mov dil, 0x5B
    call emit_byte

    ; pop rbp (5D)
    mov dil, 0x5D
    call emit_byte

    ; ret (C3)
    mov dil, 0xC3
    call emit_byte

    pop rbp
    ret

; emit_add - Emit ADD rd, rs1, rs2
; Input: dil = rd, sil = rs1, dl = rs2
emit_add:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    movzx r12d, dil             ; rd
    movzx r13d, sil             ; rs1
    movzx ebx, dl               ; rs2

    ; Skip if rd == x0 (hardwired zero)
    test r12d, r12d
    jz .done

    ; mov rax, [rbx + rs1*8]
    mov dil, 0x48
    call emit_byte
    mov dil, 0x8B
    call emit_byte
    ; ModRM: [rbx + disp32]
    mov dil, 0x83
    call emit_byte
    ; Displacement = rs1 * 8
    mov edi, r13d
    shl edi, 3
    call emit_dword

    ; add rax, [rbx + rs2*8]
    mov dil, 0x48
    call emit_byte
    mov dil, 0x03
    call emit_byte
    mov dil, 0x83
    call emit_byte
    mov edi, ebx
    shl edi, 3
    call emit_dword

    ; mov [rbx + rd*8], rax
    mov dil, 0x48
    call emit_byte
    mov dil, 0x89
    call emit_byte
    mov dil, 0x83
    call emit_byte
    mov edi, r12d
    shl edi, 3
    call emit_dword

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; emit_sub - Emit SUB rd, rs1, rs2
; Input: dil = rd, sil = rs1, dl = rs2
emit_sub:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    movzx r12d, dil             ; rd
    movzx r13d, sil             ; rs1
    movzx ebx, dl               ; rs2

    test r12d, r12d
    jz .done

    ; mov rax, [rbx + rs1*8]
    mov dil, 0x48
    call emit_byte
    mov dil, 0x8B
    call emit_byte
    mov dil, 0x83
    call emit_byte
    mov edi, r13d
    shl edi, 3
    call emit_dword

    ; sub rax, [rbx + rs2*8]
    mov dil, 0x48
    call emit_byte
    mov dil, 0x2B
    call emit_byte
    mov dil, 0x83
    call emit_byte
    mov edi, ebx
    shl edi, 3
    call emit_dword

    ; mov [rbx + rd*8], rax
    mov dil, 0x48
    call emit_byte
    mov dil, 0x89
    call emit_byte
    mov dil, 0x83
    call emit_byte
    mov edi, r12d
    shl edi, 3
    call emit_dword

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; emit_addi - Emit ADDI rd, rs1, imm
; Input: dil = rd, sil = rs1, rdx = immediate
emit_addi:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    movzx r12d, dil             ; rd
    movzx r13d, sil             ; rs1
    mov rbx, rdx                ; immediate

    test r12d, r12d
    jz .done

    ; mov rax, [rbx_reg + rs1*8]
    mov dil, 0x48
    call emit_byte
    mov dil, 0x8B
    call emit_byte
    mov dil, 0x83
    call emit_byte
    mov edi, r13d
    shl edi, 3
    call emit_dword

    ; add rax, imm32 (sign-extended)
    mov dil, 0x48
    call emit_byte
    mov dil, 0x05
    call emit_byte
    mov edi, ebx
    call emit_dword

    ; mov [rbx_reg + rd*8], rax
    mov dil, 0x48
    call emit_byte
    mov dil, 0x89
    call emit_byte
    mov dil, 0x83
    call emit_byte
    mov edi, r12d
    shl edi, 3
    call emit_dword

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; emit_and - Emit AND rd, rs1, rs2
emit_and:
    push rbp
    mov rbp, rsp
    ; TODO: Implement AND emission
    pop rbp
    ret

; emit_or - Emit OR rd, rs1, rs2
emit_or:
    push rbp
    mov rbp, rsp
    ; TODO: Implement OR emission
    pop rbp
    ret

; emit_xor - Emit XOR rd, rs1, rs2
emit_xor:
    push rbp
    mov rbp, rsp
    ; TODO: Implement XOR emission
    pop rbp
    ret

; emit_sll - Emit SLL rd, rs1, rs2
emit_sll:
    push rbp
    mov rbp, rsp
    ; TODO: Implement SLL emission
    pop rbp
    ret

; emit_srl - Emit SRL rd, rs1, rs2
emit_srl:
    push rbp
    mov rbp, rsp
    ; TODO: Implement SRL emission
    pop rbp
    ret

; emit_sra - Emit SRA rd, rs1, rs2
emit_sra:
    push rbp
    mov rbp, rsp
    ; TODO: Implement SRA emission
    pop rbp
    ret

; emit_slt - Emit SLT rd, rs1, rs2
emit_slt:
    push rbp
    mov rbp, rsp
    ; TODO: Implement SLT emission
    pop rbp
    ret

; emit_sltu - Emit SLTU rd, rs1, rs2
emit_sltu:
    push rbp
    mov rbp, rsp
    ; TODO: Implement SLTU emission
    pop rbp
    ret

; emit_load - Emit load instruction (LB/LH/LW/LD/LBU/LHU/LWU)
; Input: dil = rd, sil = rs1, rdx = offset, cl = width (1/2/4/8), r8b = signed
emit_load:
    push rbp
    mov rbp, rsp
    ; TODO: Implement load emission
    pop rbp
    ret

; emit_store - Emit store instruction (SB/SH/SW/SD)
; Input: dil = rs2, sil = rs1, rdx = offset, cl = width (1/2/4/8)
emit_store:
    push rbp
    mov rbp, rsp
    ; TODO: Implement store emission
    pop rbp
    ret

; emit_branch - Emit conditional branch
; Input: dil = rs1, sil = rs2, rdx = offset, cl = condition type
emit_branch:
    push rbp
    mov rbp, rsp
    ; TODO: Implement branch emission
    pop rbp
    ret

; emit_jal - Emit JAL rd, offset
; Input: dil = rd, rsi = offset
emit_jal:
    push rbp
    mov rbp, rsp
    ; TODO: Implement JAL emission
    pop rbp
    ret

; emit_jalr - Emit JALR rd, rs1, offset
; Input: dil = rd, sil = rs1, rdx = offset
emit_jalr:
    push rbp
    mov rbp, rsp
    ; TODO: Implement JALR emission
    pop rbp
    ret

; emit_lui - Emit LUI rd, imm
; Input: dil = rd, rsi = immediate (upper 20 bits)
emit_lui:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    movzx r12d, dil             ; rd
    mov rbx, rsi                ; immediate

    test r12d, r12d
    jz .done

    ; mov rax, imm64
    mov dil, 0x48
    call emit_byte
    mov dil, 0xB8
    call emit_byte
    mov rdi, rbx
    call emit_qword

    ; mov [rbx_reg + rd*8], rax
    mov dil, 0x48
    call emit_byte
    mov dil, 0x89
    call emit_byte
    mov dil, 0x83
    call emit_byte
    mov edi, r12d
    shl edi, 3
    call emit_dword

.done:
    pop r12
    pop rbx
    pop rbp
    ret

; emit_auipc - Emit AUIPC rd, imm
; Input: dil = rd, rsi = immediate, rdx = current PC
emit_auipc:
    push rbp
    mov rbp, rsp
    ; TODO: Implement AUIPC emission
    pop rbp
    ret
