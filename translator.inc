translate_instruction:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rsi                ; r12 = output pointer (our write head)
    mov r13d, edi               ; r13d = instruction (keep it safe)
    lea r14, [code_buffer]      ; r14 = buffer start (for size calc)

    ; Extract opcode (bits 6:0)
    mov eax, edi
    and eax, 0x7F

    ; The Grand Dispatch - where every instruction finds its destiny
    cmp eax, RV_OP_LUI
    je .lui

    cmp eax, RV_OP_AUIPC
    je .auipc

    cmp eax, RV_OP_OP_IMM
    je .op_imm

    cmp eax, RV_OP_OP
    je .op_reg

    ; Unknown opcode - emit INT3 and pray
    ; "I'm disabled!" - but for real, this shouldn't happen
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;==============================================================================
; LUI - Load Upper Immediate
; lui rd, imm  =>  rd = imm << 12
; Dead simple, just slam the upper 20 bits into the register
;==============================================================================
.lui:
    call extract_u_type         ; ECX = rd, EAX = imm (already shifted)

    test ecx, ecx               ; Writing to x0? That's a paddlin' (NOP)
    jz .emit_nop

    ; Emit: mov rax, imm64
    ;       mov [rbx + rd*8], rax
    mov byte [r12], 0x48        ; REX.W
    mov byte [r12+1], 0xB8      ; MOV RAX, imm64

    ; Sign-extend the 32-bit value to 64-bit
    cdqe                        ; RAX = sign-extended EAX
    mov [r12+2], rax            ; imm64

    ; Store to register file
    mov byte [r12+10], 0x48     ; REX.W
    mov byte [r12+11], 0x89     ; MOV r/m64, r64
    mov byte [r12+12], 0x43     ; ModRM: [rbx + disp8]
    mov eax, ecx
    shl eax, 3                  ; rd * 8
    mov [r12+13], al

    mov rax, 14
    jmp .done

;==============================================================================
; AUIPC - Add Upper Immediate to PC
; auipc rd, imm  =>  rd = PC + (imm << 12)
; Useful for position-independent code. Very modern.
;==============================================================================
.auipc:
    call extract_u_type         ; ECX = rd, EAX = imm (already shifted)

    test ecx, ecx
    jz .emit_nop

    ; We need current PC value - stored in rv_pc
    ; Emit: mov rax, [rel rv_pc]
    ;       add rax, imm32
    ;       mov [rbx + rd*8], rax

    ; mov rax, imm64 (PC + upper immediate)
    ; For now, just use the immediate (PC handling comes later)
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

;==============================================================================
; OP-IMM - Register-Immediate Operations
; The workhorses: addi, slti, sltiu, xori, ori, andi, slli, srli, srai
;==============================================================================
.op_imm:
    ; Extract funct3 to determine which operation
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

    ; Shouldn't get here
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;==============================================================================
; ADDI - Add Immediate
; addi rd, rs1, imm  =>  rd = rs1 + imm
;==============================================================================
.addi:
    call extract_i_type         ; ECX = rd, EBX = rs1, EAX = imm

    test ecx, ecx
    jz .emit_nop

    ; Special case: rs1 == x0 means this is LI (load immediate)
    test ebx, ebx
    jz .emit_li

    ; General case: load rs1, add imm, store rd
    call emit_load_rs1          ; Load rs1 into RAX

    ; add rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], eax
    add r12, 6

    call emit_store_rd          ; Store RAX to rd
    jmp .calc_size

;==============================================================================
; LI pseudo-instruction (ADDI with rs1=x0)
;==============================================================================
.emit_li:
    ; mov rax, imm32 (sign-extended)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC0
    mov [r12+3], eax
    add r12, 7

    call emit_store_rd
    jmp .calc_size

;==============================================================================
; SLTI - Set Less Than Immediate (signed)
; slti rd, rs1, imm  =>  rd = (rs1 < imm) ? 1 : 0
;==============================================================================
.slti:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    call emit_load_rs1

    ; cmp rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x3D
    mov [r12+2], eax
    add r12, 6

    ; setl al (set if less than, signed)
    mov byte [r12], 0x0F
    mov byte [r12+1], 0x9C
    mov byte [r12+2], 0xC0      ; ModRM: AL
    add r12, 3

    ; movzx rax, al
    mov byte [r12], 0x48
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB6
    mov byte [r12+3], 0xC0
    add r12, 4

    call emit_store_rd
    jmp .calc_size

;==============================================================================
; SLTIU - Set Less Than Immediate Unsigned
;==============================================================================
.sltiu:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    call emit_load_rs1

    ; cmp rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x3D
    mov [r12+2], eax
    add r12, 6

    ; setb al (set if below, unsigned)
    mov byte [r12], 0x0F
    mov byte [r12+1], 0x92
    mov byte [r12+2], 0xC0
    add r12, 3

    ; movzx rax, al
    mov byte [r12], 0x48
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB6
    mov byte [r12+3], 0xC0
    add r12, 4

    call emit_store_rd
    jmp .calc_size

;==============================================================================
; XORI - XOR Immediate
;==============================================================================
.xori:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    test ebx, ebx
    jnz .xori_general

    ; rs1 == x0: just load the immediate (0 XOR x = x)
    jmp .emit_li

.xori_general:
    call emit_load_rs1

    ; xor rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x35
    mov [r12+2], eax
    add r12, 6

    call emit_store_rd
    jmp .calc_size

;==============================================================================
; ORI - OR Immediate
;==============================================================================
.ori:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    test ebx, ebx
    jnz .ori_general
    jmp .emit_li

.ori_general:
    call emit_load_rs1

    ; or rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x0D
    mov [r12+2], eax
    add r12, 6

    call emit_store_rd
    jmp .calc_size

;==============================================================================
; ANDI - AND Immediate
;==============================================================================
.andi:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    test ebx, ebx
    jnz .andi_general

    ; rs1 == x0: result is always 0 (0 AND x = 0)
    xor eax, eax
    jmp .emit_li

.andi_general:
    call emit_load_rs1

    ; and rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x25
    mov [r12+2], eax
    add r12, 6

    call emit_store_rd
    jmp .calc_size

;==============================================================================
; SLLI - Shift Left Logical Immediate
;==============================================================================
.slli:
    call extract_i_type
    ; For shifts, immediate is only lower 6 bits (RV64)
    and eax, 0x3F

    test ecx, ecx
    jz .emit_nop

    test ebx, ebx
    jnz .slli_general

    ; rs1 == x0: shifting zero is still zero
    xor eax, eax
    jmp .emit_li

.slli_general:
    push rax                    ; Save shift amount
    call emit_load_rs1
    pop rcx                     ; Shift amount in CL

    ; shl rax, imm8
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC1
    mov byte [r12+2], 0xE0      ; ModRM: RAX, /4
    mov [r12+3], cl
    add r12, 4

    mov ecx, r15d               ; Restore rd
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; SRLI/SRAI - Shift Right Logical/Arithmetic Immediate
; Distinguished by bit 30 (part of funct7)
;==============================================================================
.srli_srai:
    call extract_i_type

    ; Check bit 30 for arithmetic vs logical
    mov r15d, r13d
    shr r15d, 30
    and r15d, 1                 ; r15d = 1 if SRAI, 0 if SRLI

    and eax, 0x3F               ; Shift amount

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
    jnz .emit_sra

    ; shr rax, imm8
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC1
    mov byte [r12+2], 0xE8      ; ModRM: RAX, /5
    mov [r12+3], cl
    add r12, 4
    jmp .srxi_store

.emit_sra:
    ; sar rax, imm8
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC1
    mov byte [r12+2], 0xF8      ; ModRM: RAX, /7
    mov [r12+3], cl
    add r12, 4

.srxi_store:
    ; Recover rd from instruction
    mov eax, r13d
    shr eax, 7
    and eax, 0x1F
    mov ecx, eax
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; OP - Register-Register Operations
; add, sub, sll, slt, sltu, xor, srl, sra, or, and
;==============================================================================
.op_reg:
    ; Extract funct3
    mov eax, r13d
    shr eax, 12
    and eax, 0x7

    ; Extract funct7 for ADD/SUB and SRL/SRA disambiguation
    mov r15d, r13d
    shr r15d, 25
    and r15d, 0x7F

    cmp eax, RV_F3_ADD_SUB
    je .add_sub

    cmp eax, RV_F3_SLL
    je .sll

    cmp eax, RV_F3_SLT
    je .slt

    cmp eax, RV_F3_SLTU
    je .sltu

    cmp eax, RV_F3_XOR
    je .xor_reg

    cmp eax, RV_F3_SRL_SRA
    je .srl_sra

    cmp eax, RV_F3_OR
    je .or_reg

    cmp eax, RV_F3_AND
    je .and_reg

    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;==============================================================================
; ADD/SUB - determined by funct7
;==============================================================================
.add_sub:
    call extract_r_type         ; ECX = rd, EBX = rs1, EAX = rs2

    test ecx, ecx
    jz .emit_nop

    push rax                    ; Save rs2
    call emit_load_rs1
    pop rax                     ; rs2 in EAX

    ; Load rs2 into RCX
    push rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B      ; RCX from [rbx + disp8]
    mov edx, eax
    shl edx, 3
    mov [r12+3], dl
    add r12, 4

    ; Check funct7 for SUB
    cmp r15d, RV_F7_ALT
    je .emit_sub

    ; add rax, rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xC8      ; ModRM: RAX, RCX
    add r12, 3
    jmp .add_sub_store

.emit_sub:
    ; sub rax, rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x29
    mov byte [r12+2], 0xC8
    add r12, 3

.add_sub_store:
    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; SLL - Shift Left Logical (register)
;==============================================================================
.sll:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx                    ; Save rd
    push rax                    ; Save rs2
    call emit_load_rs1

    ; Load rs2 into RCX (shift amount)
    pop rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov edx, eax
    shl edx, 3
    mov [r12+3], dl
    add r12, 4

    ; shl rax, cl
    mov byte [r12], 0x48
    mov byte [r12+1], 0xD3
    mov byte [r12+2], 0xE0
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; SLT - Set Less Than (signed)
;==============================================================================
.slt:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1

    ; Load rs2 into RCX
    pop rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov edx, eax
    shl edx, 3
    mov [r12+3], dl
    add r12, 4

    ; cmp rax, rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xC8
    add r12, 3

    ; setl al
    mov byte [r12], 0x0F
    mov byte [r12+1], 0x9C
    mov byte [r12+2], 0xC0
    add r12, 3

    ; movzx rax, al
    mov byte [r12], 0x48
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB6
    mov byte [r12+3], 0xC0
    add r12, 4

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; SLTU - Set Less Than Unsigned
;==============================================================================
.sltu:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1

    pop rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov edx, eax
    shl edx, 3
    mov [r12+3], dl
    add r12, 4

    ; cmp rax, rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xC8
    add r12, 3

    ; setb al (unsigned)
    mov byte [r12], 0x0F
    mov byte [r12+1], 0x92
    mov byte [r12+2], 0xC0
    add r12, 3

    ; movzx rax, al
    mov byte [r12], 0x48
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB6
    mov byte [r12+3], 0xC0
    add r12, 4

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; XOR (register)
;==============================================================================
.xor_reg:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1

    pop rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov edx, eax
    shl edx, 3
    mov [r12+3], dl
    add r12, 4

    ; xor rax, rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x31
    mov byte [r12+2], 0xC8
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; SRL/SRA - Shift Right (logical/arithmetic)
;==============================================================================
.srl_sra:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1

    pop rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov edx, eax
    shl edx, 3
    mov [r12+3], dl
    add r12, 4

    cmp r15d, RV_F7_ALT
    je .emit_sra_reg

    ; shr rax, cl
    mov byte [r12], 0x48
    mov byte [r12+1], 0xD3
    mov byte [r12+2], 0xE8
    add r12, 3
    jmp .srl_sra_store

.emit_sra_reg:
    ; sar rax, cl
    mov byte [r12], 0x48
    mov byte [r12+1], 0xD3
    mov byte [r12+2], 0xF8
    add r12, 3

.srl_sra_store:
    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; OR (register)
;==============================================================================
.or_reg:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1

    pop rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov edx, eax
    shl edx, 3
    mov [r12+3], dl
    add r12, 4

    ; or rax, rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x09
    mov byte [r12+2], 0xC8
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; AND (register)
;==============================================================================
.and_reg:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1

    pop rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov edx, eax
    shl edx, 3
    mov [r12+3], dl
    add r12, 4

    ; and rax, rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x21
    mov byte [r12+2], 0xC8
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; NOP - when rd is x0, nothing happens
; "Nothing happened! Nothing to see here!"
;==============================================================================
.emit_nop:
    mov byte [r12], 0x90
    mov rax, 1
    jmp .done

;==============================================================================
; Calculate bytes written
;==============================================================================
.calc_size:
    mov rax, r12
    sub rax, r14
    jmp .done

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

;==============================================================================
; Helper: emit_load_rs1
; Emits: mov rax, [rbx + rs1*8]
; Expects: EBX = rs1
; Updates: r12
;==============================================================================
emit_load_rs1:
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov [r12+3], al
    add r12, 4
    ret

;==============================================================================
; Helper: emit_store_rd
; Emits: mov [rbx + rd*8], rax
; Expects: ECX = rd, r15d preserved for caller
;==============================================================================
emit_store_rd:
    mov r15d, ecx               ; Preserve rd in r15
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x43
    mov eax, ecx
    shl eax, 3
    mov [r12+3], al
    add r12, 4
    ret

;==============================================================================
; extract_i_type - I-type instruction format
; Input:  R13D = instruction
; Output: ECX = rd, EBX = rs1, EAX = immediate (sign-extended)
;==============================================================================
extract_i_type:
    ; rd = bits 11:7
    mov eax, r13d
    shr eax, 7
    and eax, 0x1F
    mov ecx, eax

    ; rs1 = bits 19:15
    mov eax, r13d
    shr eax, 15
    and eax, 0x1F
    mov ebx, eax

    ; imm = bits 31:20 (sign-extended)
    mov eax, r13d
    sar eax, 20
    ret

;==============================================================================
; extract_r_type - R-type instruction format
; Input:  R13D = instruction
; Output: ECX = rd, EBX = rs1, EAX = rs2
;==============================================================================
extract_r_type:
    ; rd = bits 11:7
    mov eax, r13d
    shr eax, 7
    and eax, 0x1F
    mov ecx, eax

    ; rs1 = bits 19:15
    mov eax, r13d
    shr eax, 15
    and eax, 0x1F
    mov ebx, eax

    ; rs2 = bits 24:20
    mov eax, r13d
    shr eax, 20
    and eax, 0x1F
    ret

;==============================================================================
; extract_u_type - U-type instruction format (LUI, AUIPC)
; Input:  R13D = instruction
; Output: ECX = rd, EAX = immediate (upper 20 bits, already shifted)
;==============================================================================
extract_u_type:
    ; rd = bits 11:7
    mov eax, r13d
    shr eax, 7
    and eax, 0x1F
    mov ecx, eax

    ; imm = bits 31:12, placed in upper 20 bits
    mov eax, r13d
    and eax, 0xFFFFF000
    ret
