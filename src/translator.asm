; translator.asm
; Conway translator - library version (no main)
; Just the translate_instruction function for linking with test harnesses

bits 64
default rel

;==============================================================================
; Constants
;==============================================================================

; RISC-V opcodes
RV_OP_LUI       equ 0x37
RV_OP_AUIPC     equ 0x17
RV_OP_OP_IMM    equ 0x13
RV_OP_OP        equ 0x33
RV_OP_LOAD      equ 0x03
RV_OP_STORE     equ 0x23

; Funct3 for OP-IMM
RV_F3_ADDI      equ 0x0
RV_F3_SLTI      equ 0x2
RV_F3_SLTIU     equ 0x3
RV_F3_XORI      equ 0x4
RV_F3_ORI       equ 0x6
RV_F3_ANDI      equ 0x7
RV_F3_SLLI      equ 0x1
RV_F3_SRLI_SRAI equ 0x5

; Funct3 for OP
RV_F3_ADD_SUB   equ 0x0
RV_F3_SLL       equ 0x1
RV_F3_SLT       equ 0x2
RV_F3_SLTU      equ 0x3
RV_F3_XOR       equ 0x4
RV_F3_SRL_SRA   equ 0x5
RV_F3_OR        equ 0x6
RV_F3_AND       equ 0x7

; Funct7 values
RV_F7_NORMAL    equ 0x00
RV_F7_ALT       equ 0x20

; Funct3 for loads
RV_F3_LB        equ 0x0
RV_F3_LH        equ 0x1
RV_F3_LW        equ 0x2
RV_F3_LD        equ 0x3
RV_F3_LBU       equ 0x4
RV_F3_LHU       equ 0x5
RV_F3_LWU       equ 0x6

; Funct3 for stores
RV_F3_SB        equ 0x0
RV_F3_SH        equ 0x1
RV_F3_SW        equ 0x2
RV_F3_SD        equ 0x3

section .text
    global translate_instruction

;==============================================================================
; translate_instruction
; Input:  EDI = 32-bit RISC-V instruction
;         RSI = output buffer pointer
; Output: RAX = bytes written
;==============================================================================
translate_instruction:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rsi                ; r12 = output pointer
    mov r13d, edi               ; r13d = instruction
    mov r14, rsi                ; r14 = buffer start for size calc

    ; Extract opcode
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

    cmp eax, RV_OP_LOAD
    je .load

    cmp eax, RV_OP_STORE
    je .store

    ; Unknown - emit INT3
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;==============================================================================
; LUI
;==============================================================================
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

;==============================================================================
; AUIPC
;==============================================================================
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

;==============================================================================
; OP-IMM dispatch
;==============================================================================
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

;==============================================================================
; ADDI
;==============================================================================
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

;==============================================================================
; SLTI
;==============================================================================
.slti:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rax
    call emit_load_rs1
    pop rax

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

;==============================================================================
; SLTIU
;==============================================================================
.sltiu:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rax
    call emit_load_rs1
    pop rax

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

;==============================================================================
; XORI
;==============================================================================
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

;==============================================================================
; ORI
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

    mov byte [r12], 0x48
    mov byte [r12+1], 0x0D
    mov [r12+2], eax
    add r12, 6

    call emit_store_rd
    jmp .calc_size

;==============================================================================
; ANDI
;==============================================================================
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

;==============================================================================
; SLLI
;==============================================================================
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

;==============================================================================
; SRLI/SRAI
;==============================================================================
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
    jnz .emit_sra

    mov byte [r12], 0x48
    mov byte [r12+1], 0xC1
    mov byte [r12+2], 0xE8
    mov [r12+3], cl
    add r12, 4
    jmp .srxi_store

.emit_sra:
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

;==============================================================================
; OP (register-register) dispatch
;==============================================================================
.op_reg:
    mov eax, r13d
    shr eax, 12
    and eax, 0x7

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
; ADD/SUB
;==============================================================================
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

;==============================================================================
; SLL
;==============================================================================
.sll:
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

    mov byte [r12], 0x48
    mov byte [r12+1], 0xD3
    mov byte [r12+2], 0xE0
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; SLT
;==============================================================================
.slt:
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

    mov byte [r12], 0x48
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xC8
    add r12, 3

    mov byte [r12], 0x0F
    mov byte [r12+1], 0x9C
    mov byte [r12+2], 0xC0
    add r12, 3

    mov byte [r12], 0x48
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB6
    mov byte [r12+3], 0xC0
    add r12, 4

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; SLTU
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

    mov byte [r12], 0x48
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xC8
    add r12, 3

    mov byte [r12], 0x0F
    mov byte [r12+1], 0x92
    mov byte [r12+2], 0xC0
    add r12, 3

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

    mov byte [r12], 0x48
    mov byte [r12+1], 0x31
    mov byte [r12+2], 0xC8
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; SRL/SRA
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

    mov byte [r12], 0x48
    mov byte [r12+1], 0xD3
    mov byte [r12+2], 0xE8
    add r12, 3
    jmp .srl_sra_store

.emit_sra_reg:
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

    mov byte [r12], 0x48
    mov byte [r12+1], 0x21
    mov byte [r12+2], 0xC8
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LOAD dispatch
;==============================================================================
.load:
    mov eax, r13d
    shr eax, 12
    and eax, 0x7

    cmp eax, RV_F3_LB
    je .lb
    cmp eax, RV_F3_LH
    je .lh
    cmp eax, RV_F3_LW
    je .lw
    cmp eax, RV_F3_LD
    je .ld
    cmp eax, RV_F3_LBU
    je .lbu
    cmp eax, RV_F3_LHU
    je .lhu
    cmp eax, RV_F3_LWU
    je .lwu

    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;==============================================================================
; LB - Load Byte (sign-extended)
;==============================================================================
.lb:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    mov byte [r12], 0x49
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xBE
    mov byte [r12+3], 0x04
    mov byte [r12+4], 0x06
    add r12, 5

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LH - Load Halfword (sign-extended)
;==============================================================================
.lh:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    mov byte [r12], 0x49
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xBF
    mov byte [r12+3], 0x04
    mov byte [r12+4], 0x06
    add r12, 5

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LW - Load Word (sign-extended)
;==============================================================================
.lw:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    mov byte [r12], 0x49
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0x04
    mov byte [r12+3], 0x06
    add r12, 4

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LD - Load Doubleword
;==============================================================================
.ld:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    mov byte [r12], 0x49
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x04
    mov byte [r12+3], 0x06
    add r12, 4

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LBU - Load Byte Unsigned
;==============================================================================
.lbu:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    mov byte [r12], 0x49
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB6
    mov byte [r12+3], 0x04
    mov byte [r12+4], 0x06
    add r12, 5

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LHU - Load Halfword Unsigned
;==============================================================================
.lhu:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    mov byte [r12], 0x49
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB7
    mov byte [r12+3], 0x04
    mov byte [r12+4], 0x06
    add r12, 5

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LWU - Load Word Unsigned
;==============================================================================
.lwu:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    mov byte [r12], 0x41
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x04
    mov byte [r12+3], 0x06
    add r12, 4

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; STORE dispatch
;==============================================================================
.store:
    mov eax, r13d
    shr eax, 12
    and eax, 0x7

    cmp eax, RV_F3_SB
    je .sb
    cmp eax, RV_F3_SH
    je .sh
    cmp eax, RV_F3_SW
    je .sw
    cmp eax, RV_F3_SD
    je .sd

    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;==============================================================================
; SB - Store Byte
;==============================================================================
.sb:
    call extract_s_type

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    pop rdx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    shl edx, 3
    mov [r12+3], dl
    add r12, 4

    mov byte [r12], 0x41
    mov byte [r12+1], 0x88
    mov byte [r12+2], 0x0C
    mov byte [r12+3], 0x06
    add r12, 4

    jmp .calc_size

;==============================================================================
; SH - Store Halfword
;==============================================================================
.sh:
    call extract_s_type

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    pop rdx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    shl edx, 3
    mov [r12+3], dl
    add r12, 4

    mov byte [r12], 0x66
    mov byte [r12+1], 0x41
    mov byte [r12+2], 0x89
    mov byte [r12+3], 0x0C
    mov byte [r12+4], 0x06
    add r12, 5

    jmp .calc_size

;==============================================================================
; SW - Store Word
;==============================================================================
.sw:
    call extract_s_type

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    pop rdx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    shl edx, 3
    mov [r12+3], dl
    add r12, 4

    mov byte [r12], 0x41
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x0C
    mov byte [r12+3], 0x06
    add r12, 4

    jmp .calc_size

;==============================================================================
; SD - Store Doubleword
;==============================================================================
.sd:
    call extract_s_type

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    pop rdx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    shl edx, 3
    mov [r12+3], dl
    add r12, 4

    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x0C
    mov byte [r12+3], 0x06
    add r12, 4

    jmp .calc_size

;==============================================================================
; NOP
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
; emit_load_rs1 - Load rs1 into RAX
; Expects: EBX = rs1
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
; emit_store_rd - Store RAX to rd
; Expects: ECX = rd
;==============================================================================
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

;==============================================================================
; extract_i_type
;==============================================================================
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

;==============================================================================
; extract_r_type
;==============================================================================
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

;==============================================================================
; extract_u_type
;==============================================================================
extract_u_type:
    mov eax, r13d
    shr eax, 7
    and eax, 0x1F
    mov ecx, eax

    mov eax, r13d
    and eax, 0xFFFFF000
    ret

;==============================================================================
; extract_s_type
;==============================================================================
extract_s_type:
    mov eax, r13d
    shr eax, 15
    and eax, 0x1F
    mov ebx, eax

    mov eax, r13d
    shr eax, 20
    and eax, 0x1F
    mov ecx, eax

    mov eax, r13d
    shr eax, 7
    and eax, 0x1F
    mov edx, eax

    mov eax, r13d
    sar eax, 20
    and eax, 0xFFFFFFE0
    or eax, edx
    ret
