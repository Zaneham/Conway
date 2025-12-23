; Conway - RISC-V to x86-64 Binary Translator
; dispatch.asm - Instruction dispatch handler
;
; Routes decoded instructions to appropriate emission handlers

%include "rv_opcodes.inc"

section .data
    ; Jump table for R-type funct3 dispatch
    align 8
    r_type_table:
        dq handle_add_sub       ; funct3 = 0 (ADD/SUB)
        dq handle_sll           ; funct3 = 1 (SLL)
        dq handle_slt           ; funct3 = 2 (SLT)
        dq handle_sltu          ; funct3 = 3 (SLTU)
        dq handle_xor           ; funct3 = 4 (XOR)
        dq handle_srl_sra       ; funct3 = 5 (SRL/SRA)
        dq handle_or            ; funct3 = 6 (OR)
        dq handle_and           ; funct3 = 7 (AND)

    ; Jump table for I-type (OP-IMM) funct3 dispatch
    align 8
    i_type_table:
        dq handle_addi          ; funct3 = 0 (ADDI)
        dq handle_slli          ; funct3 = 1 (SLLI)
        dq handle_slti          ; funct3 = 2 (SLTI)
        dq handle_sltiu         ; funct3 = 3 (SLTIU)
        dq handle_xori          ; funct3 = 4 (XORI)
        dq handle_srli_srai     ; funct3 = 5 (SRLI/SRAI)
        dq handle_ori           ; funct3 = 6 (ORI)
        dq handle_andi          ; funct3 = 7 (ANDI)

    ; Jump table for branch funct3 dispatch
    align 8
    branch_table:
        dq handle_beq           ; funct3 = 0 (BEQ)
        dq handle_bne           ; funct3 = 1 (BNE)
        dq handle_invalid       ; funct3 = 2 (invalid)
        dq handle_invalid       ; funct3 = 3 (invalid)
        dq handle_blt           ; funct3 = 4 (BLT)
        dq handle_bge           ; funct3 = 5 (BGE)
        dq handle_bltu          ; funct3 = 6 (BLTU)
        dq handle_bgeu          ; funct3 = 7 (BGEU)

    ; Jump table for load funct3 dispatch
    align 8
    load_table:
        dq handle_lb            ; funct3 = 0 (LB)
        dq handle_lh            ; funct3 = 1 (LH)
        dq handle_lw            ; funct3 = 2 (LW)
        dq handle_ld            ; funct3 = 3 (LD)
        dq handle_lbu           ; funct3 = 4 (LBU)
        dq handle_lhu           ; funct3 = 5 (LHU)
        dq handle_lwu           ; funct3 = 6 (LWU)
        dq handle_invalid       ; funct3 = 7 (invalid)

    ; Jump table for store funct3 dispatch
    align 8
    store_table:
        dq handle_sb            ; funct3 = 0 (SB)
        dq handle_sh            ; funct3 = 1 (SH)
        dq handle_sw            ; funct3 = 2 (SW)
        dq handle_sd            ; funct3 = 3 (SD)
        dq handle_invalid       ; funct3 = 4 (invalid)
        dq handle_invalid       ; funct3 = 5 (invalid)
        dq handle_invalid       ; funct3 = 6 (invalid)
        dq handle_invalid       ; funct3 = 7 (invalid)

section .bss

section .text
    global dispatch_handler

    extern get_opcode
    extern get_rd
    extern get_rs1
    extern get_rs2
    extern get_funct3
    extern get_funct7
    extern get_immediate

    extern emit_add
    extern emit_sub
    extern emit_and
    extern emit_or
    extern emit_xor
    extern emit_sll
    extern emit_srl
    extern emit_sra
    extern emit_slt
    extern emit_sltu
    extern emit_addi
    extern emit_load
    extern emit_store
    extern emit_branch
    extern emit_jal
    extern emit_jalr
    extern emit_lui
    extern emit_auipc

; dispatch_handler - Route decoded instruction to appropriate handler
; Input: rdi = pointer to decoded instruction
dispatch_handler:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                ; Save decoded instruction pointer

    ; Get opcode
    call get_opcode

    ; Dispatch based on opcode
    cmp al, RV_OP_LUI
    je .handle_lui
    cmp al, RV_OP_AUIPC
    je .handle_auipc
    cmp al, RV_OP_JAL
    je .handle_jal
    cmp al, RV_OP_JALR
    je .handle_jalr
    cmp al, RV_OP_BRANCH
    je .handle_branch
    cmp al, RV_OP_LOAD
    je .handle_load
    cmp al, RV_OP_STORE
    je .handle_store
    cmp al, RV_OP_OP_IMM
    je .handle_op_imm
    cmp al, RV_OP_OP
    je .handle_op
    cmp al, RV_OP_OP_IMM_32
    je .handle_op_imm_32
    cmp al, RV_OP_OP_32
    je .handle_op_32

    ; Unknown opcode
    jmp .done

.handle_lui:
    call get_rd
    mov r12d, eax               ; rd
    call get_immediate
    mov rsi, rax                ; immediate
    mov dil, r12b
    call emit_lui
    jmp .done

.handle_auipc:
    call get_rd
    mov r12d, eax
    call get_immediate
    mov rsi, rax
    xor edx, edx                ; TODO: Pass current PC
    mov dil, r12b
    call emit_auipc
    jmp .done

.handle_jal:
    call get_rd
    mov r12d, eax
    call get_immediate
    mov rsi, rax
    mov dil, r12b
    call emit_jal
    jmp .done

.handle_jalr:
    call get_rd
    mov r12d, eax
    call get_rs1
    mov r13d, eax
    call get_immediate
    mov rdx, rax
    mov dil, r12b
    mov sil, r13b
    call emit_jalr
    jmp .done

.handle_branch:
    call get_funct3
    movzx eax, al
    cmp eax, 8
    jge .done
    lea rcx, [rel branch_table]
    jmp [rcx + rax*8]

.handle_load:
    call get_funct3
    movzx eax, al
    cmp eax, 8
    jge .done
    lea rcx, [rel load_table]
    jmp [rcx + rax*8]

.handle_store:
    call get_funct3
    movzx eax, al
    cmp eax, 8
    jge .done
    lea rcx, [rel store_table]
    jmp [rcx + rax*8]

.handle_op_imm:
    call get_funct3
    movzx eax, al
    cmp eax, 8
    jge .done
    lea rcx, [rel i_type_table]
    jmp [rcx + rax*8]

.handle_op:
    call get_funct3
    movzx eax, al
    cmp eax, 8
    jge .done
    lea rcx, [rel r_type_table]
    jmp [rcx + rax*8]

.handle_op_imm_32:
    ; 32-bit immediate operations (RV64I)
    ; TODO: Implement
    jmp .done

.handle_op_32:
    ; 32-bit register operations (RV64I)
    ; TODO: Implement
    jmp .done

; R-type handlers
handle_add_sub:
    call get_funct7
    test al, 0x20               ; Check bit 5 (distinguishes ADD from SUB)
    jnz .is_sub

    ; ADD
    call get_rd
    mov r12d, eax
    call get_rs1
    mov r13d, eax
    call get_rs2
    mov dil, r12b
    mov sil, r13b
    mov dl, al
    call emit_add
    jmp .done

.is_sub:
    call get_rd
    mov r12d, eax
    call get_rs1
    mov r13d, eax
    call get_rs2
    mov dil, r12b
    mov sil, r13b
    mov dl, al
    call emit_sub
    jmp .done

handle_sll:
    call get_rd
    mov r12d, eax
    call get_rs1
    mov r13d, eax
    call get_rs2
    mov dil, r12b
    mov sil, r13b
    mov dl, al
    call emit_sll
    jmp .done

handle_slt:
    call get_rd
    mov r12d, eax
    call get_rs1
    mov r13d, eax
    call get_rs2
    mov dil, r12b
    mov sil, r13b
    mov dl, al
    call emit_slt
    jmp .done

handle_sltu:
    call get_rd
    mov r12d, eax
    call get_rs1
    mov r13d, eax
    call get_rs2
    mov dil, r12b
    mov sil, r13b
    mov dl, al
    call emit_sltu
    jmp .done

handle_xor:
    call get_rd
    mov r12d, eax
    call get_rs1
    mov r13d, eax
    call get_rs2
    mov dil, r12b
    mov sil, r13b
    mov dl, al
    call emit_xor
    jmp .done

handle_srl_sra:
    call get_funct7
    test al, 0x20
    jnz .is_sra

    call get_rd
    mov r12d, eax
    call get_rs1
    mov r13d, eax
    call get_rs2
    mov dil, r12b
    mov sil, r13b
    mov dl, al
    call emit_srl
    jmp .done

.is_sra:
    call get_rd
    mov r12d, eax
    call get_rs1
    mov r13d, eax
    call get_rs2
    mov dil, r12b
    mov sil, r13b
    mov dl, al
    call emit_sra
    jmp .done

handle_or:
    call get_rd
    mov r12d, eax
    call get_rs1
    mov r13d, eax
    call get_rs2
    mov dil, r12b
    mov sil, r13b
    mov dl, al
    call emit_or
    jmp .done

handle_and:
    call get_rd
    mov r12d, eax
    call get_rs1
    mov r13d, eax
    call get_rs2
    mov dil, r12b
    mov sil, r13b
    mov dl, al
    call emit_and
    jmp .done

; I-type handlers
handle_addi:
    call get_rd
    mov r12d, eax
    call get_rs1
    mov r13d, eax
    call get_immediate
    mov rdx, rax
    mov dil, r12b
    mov sil, r13b
    call emit_addi
    jmp .done

handle_slli:
handle_slti:
handle_sltiu:
handle_xori:
handle_srli_srai:
handle_ori:
handle_andi:
    ; TODO: Implement remaining I-type handlers
    jmp .done

; Branch handlers
handle_beq:
handle_bne:
handle_blt:
handle_bge:
handle_bltu:
handle_bgeu:
    ; TODO: Implement branch handlers
    jmp .done

; Load handlers
handle_lb:
handle_lh:
handle_lw:
handle_ld:
handle_lbu:
handle_lhu:
handle_lwu:
    ; TODO: Implement load handlers
    jmp .done

; Store handlers
handle_sb:
handle_sh:
handle_sw:
handle_sd:
    ; TODO: Implement store handlers
    jmp .done

handle_invalid:
    ; Invalid instruction - skip
    jmp .done

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
