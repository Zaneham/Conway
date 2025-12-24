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
RV_OP_JAL       equ 0x6F        ; Jump and Link
RV_OP_JALR      equ 0x67        ; Jump and Link Register
RV_OP_BRANCH    equ 0x63        ; Conditional branches

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

; Funct3 for branches
RV_F3_BEQ       equ 0x0         ; Branch if Equal
RV_F3_BNE       equ 0x1         ; Branch if Not Equal
RV_F3_BLT       equ 0x4         ; Branch if Less Than (signed)
RV_F3_BGE       equ 0x5         ; Branch if Greater or Equal (signed)
RV_F3_BLTU      equ 0x6         ; Branch if Less Than Unsigned
RV_F3_BGEU      equ 0x7         ; Branch if Greater or Equal Unsigned

section .text
    global translate_instruction
    global translate_block
    global lookup_block
    global init_block_cache
    global execute_blocks
    global link_block
    global block_cache
    global code_buffer

;==============================================================================
; Block Cache Constants
;==============================================================================
BLOCK_CACHE_SIZE    equ 1024            ; Number of cache entries
BLOCK_ENTRY_SIZE    equ 64              ; Bytes per entry
CODE_BUFFER_SIZE    equ 1048576         ; 1MB code buffer

; Block entry offsets
BLOCK_VALID         equ 0               ; 1 byte: is entry valid?
BLOCK_START_PC      equ 8               ; 8 bytes: RISC-V start PC
BLOCK_CODE_PTR      equ 16              ; 8 bytes: pointer to x86 code
BLOCK_CODE_SIZE     equ 24              ; 4 bytes: size of x86 code
BLOCK_EXIT_TYPE     equ 28              ; 4 bytes: how block exits
BLOCK_NEXT_PC       equ 32              ; 8 bytes: unconditional target
BLOCK_TAKEN_PC      equ 40              ; 8 bytes: branch taken target
BLOCK_NOT_TAKEN_PC  equ 48              ; 8 bytes: branch not-taken target
; 56-63: padding to 64 bytes

; Exit types
EXIT_NONE           equ 0               ; Block doesn't exit (incomplete)
EXIT_JUMP           equ 1               ; Unconditional jump (JAL/JALR)
EXIT_BRANCH         equ 2               ; Conditional branch
EXIT_INDIRECT       equ 3               ; Indirect jump (JALR with register)

section .bss
    alignb 4096
    block_cache:    resb BLOCK_CACHE_SIZE * BLOCK_ENTRY_SIZE    ; 64KB cache
    code_buffer:    resb CODE_BUFFER_SIZE                        ; 1MB code
    code_buf_ptr:   resq 1                                       ; Allocation pointer

section .text

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

    cmp eax, RV_OP_JAL
    je .jal

    cmp eax, RV_OP_JALR
    je .jalr

    cmp eax, RV_OP_BRANCH
    je .branch

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
; JAL - Jump and Link (J-type)
; rd = PC + 4; PC = PC + imm
; "Sometimes you just need to take a leap of faith" - but save where you were
;
; Calling convention: R15 = pointer to rv_pc
;==============================================================================
.jal:
    call extract_j_type         ; ECX = rd, EAX = imm (sign-extended)

    ; First, save the return address (PC + 4) to rd if rd != x0
    test ecx, ecx
    jz .jal_skip_rd

    ; Emit: mov rax, [r15]      ; Load current PC
    mov byte [r12], 0x49
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x07      ; ModRM: [r15]
    add r12, 3

    ; Emit: add rax, 4          ; PC + 4
    mov byte [r12], 0x48
    mov byte [r12+1], 0x83
    mov byte [r12+2], 0xC0
    mov byte [r12+3], 0x04
    add r12, 4

    ; Emit: mov [rbx + rd*8], rax
    push rax                    ; Save imm
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x43
    mov eax, ecx
    shl eax, 3
    mov [r12+3], al
    add r12, 4
    pop rax                     ; Restore imm

.jal_skip_rd:
    ; Now update PC = PC + imm
    ; Emit: mov rcx, [r15]      ; Load current PC
    mov byte [r12], 0x49
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x0F
    add r12, 3

    ; Emit: add rcx, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x81
    mov byte [r12+2], 0xC1
    mov [r12+3], eax
    add r12, 7

    ; Emit: mov [r15], rcx      ; Store new PC
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x0F
    add r12, 3

    jmp .calc_size

;==============================================================================
; JALR - Jump and Link Register (I-type)
; rd = PC + 4; PC = (rs1 + imm) & ~1
;==============================================================================
.jalr:
    call extract_i_type         ; ECX = rd, EBX = rs1, EAX = imm

    push rcx                    ; Save rd
    push rax                    ; Save imm

    ; Save return address (PC + 4) to rd if rd != x0
    test ecx, ecx
    jz .jalr_skip_rd

    ; Emit: mov rax, [r15]
    mov byte [r12], 0x49
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x07
    add r12, 3

    ; Emit: add rax, 4
    mov byte [r12], 0x48
    mov byte [r12+1], 0x83
    mov byte [r12+2], 0xC0
    mov byte [r12+3], 0x04
    add r12, 4

    ; Emit: mov [rbx + rd*8], rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x43
    pop rax
    push rax
    mov eax, [rsp+8]            ; Get rd from stack
    shl eax, 3
    mov [r12+3], al
    add r12, 4

.jalr_skip_rd:
    ; Compute target: (rs1 + imm) & ~1
    ; Emit: mov rcx, [rbx + rs1*8]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov eax, ebx
    shl eax, 3
    mov [r12+3], al
    add r12, 4

    ; Emit: add rcx, imm32
    pop rax                     ; Get imm
    mov byte [r12], 0x48
    mov byte [r12+1], 0x81
    mov byte [r12+2], 0xC1
    mov [r12+3], eax
    add r12, 7

    ; Emit: and rcx, ~1 (clear lowest bit)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x83
    mov byte [r12+2], 0xE1
    mov byte [r12+3], 0xFE      ; -2 = ~1
    add r12, 4

    ; Emit: mov [r15], rcx
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x0F
    add r12, 3

    pop rcx                     ; Clean up stack (rd)
    jmp .calc_size

;==============================================================================
; BRANCH - Conditional branches (B-type)
; if (condition) PC = PC + imm else PC = PC + 4
; "To branch, or not to branch, that is the question"
;==============================================================================
.branch:
    ; Extract funct3 to determine branch type
    mov eax, r13d
    shr eax, 12
    and eax, 0x7
    push rax                    ; Save funct3

    call extract_b_type         ; ECX = rs2, EBX = rs1, EAX = imm

    push rax                    ; Save imm

    ; Emit: mov rax, [rbx + rs1*8]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov [r12+3], al
    add r12, 4

    ; Emit: mov rcx, [rbx + rs2*8]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov eax, ecx
    shl eax, 3
    mov [r12+3], al
    add r12, 4

    ; Emit: cmp rax, rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xC8
    add r12, 3

    ; Now emit conditional jump based on funct3
    ; We'll emit: jCC taken; mov rdx, 4; jmp done; taken: mov rdx, imm; done: ...
    pop rax                     ; imm
    pop rdx                     ; funct3

    ; Emit conditional jump to taken (short jump, 2 bytes)
    ; The "not taken" path is 10 bytes: mov rdx,4 (7) + jmp +3 (2) + nop (1)
    cmp edx, RV_F3_BEQ
    je .emit_beq
    cmp edx, RV_F3_BNE
    je .emit_bne
    cmp edx, RV_F3_BLT
    je .emit_blt
    cmp edx, RV_F3_BGE
    je .emit_bge
    cmp edx, RV_F3_BLTU
    je .emit_bltu
    cmp edx, RV_F3_BGEU
    je .emit_bgeu

    ; Unknown branch - INT3
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

.emit_beq:
    mov byte [r12], 0x74        ; JE rel8
    jmp .branch_common
.emit_bne:
    mov byte [r12], 0x75        ; JNE rel8
    jmp .branch_common
.emit_blt:
    mov byte [r12], 0x7C        ; JL rel8 (signed)
    jmp .branch_common
.emit_bge:
    mov byte [r12], 0x7D        ; JGE rel8 (signed)
    jmp .branch_common
.emit_bltu:
    mov byte [r12], 0x72        ; JB rel8 (unsigned)
    jmp .branch_common
.emit_bgeu:
    mov byte [r12], 0x73        ; JAE rel8 (unsigned)
    jmp .branch_common

.branch_common:
    ; Jcc +10 (skip not-taken path)
    mov byte [r12+1], 10
    add r12, 2

    ; Not taken: mov rdx, 4
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC2
    mov dword [r12+3], 4
    add r12, 7

    ; jmp +8 (skip taken path - nop is 1 byte + mov rdx,imm is 7 bytes = 8)
    mov byte [r12], 0xEB
    mov byte [r12+1], 8
    add r12, 2

    ; nop for alignment
    mov byte [r12], 0x90
    add r12, 1

    ; Taken: mov rdx, imm
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC2
    mov [r12+3], eax            ; imm
    add r12, 7

    ; Done: update PC
    ; Emit: mov rax, [r15]      ; Current PC
    mov byte [r12], 0x49
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x07
    add r12, 3

    ; Emit: add rax, rdx        ; PC + offset (4 or imm)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xD0
    add r12, 3

    ; Emit: mov [r15], rax      ; Store new PC
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x07
    add r12, 3

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

;==============================================================================
; extract_j_type - J-type instruction format (JAL)
; Input:  R13D = instruction
; Output: ECX = rd, EAX = immediate (sign-extended, scaled by 2)
;
; J-type immediate: imm[20|10:1|11|19:12] - bits are scrambled!
; Final imm = {inst[31], inst[19:12], inst[20], inst[30:21], 0}
;==============================================================================
extract_j_type:
    ; rd = bits 11:7
    mov eax, r13d
    shr eax, 7
    and eax, 0x1F
    mov ecx, eax

    ; Build the immediate from its scattered bits
    ; imm[20]    = inst[31]
    ; imm[10:1]  = inst[30:21]
    ; imm[11]    = inst[20]
    ; imm[19:12] = inst[19:12]

    xor eax, eax

    ; imm[19:12] = inst[19:12]
    mov edx, r13d
    and edx, 0x000FF000          ; Bits 19:12
    or eax, edx

    ; imm[11] = inst[20]
    mov edx, r13d
    shr edx, 9                   ; Bit 20 -> bit 11
    and edx, 0x00000800
    or eax, edx

    ; imm[10:1] = inst[30:21]
    mov edx, r13d
    shr edx, 20                  ; Bits 30:21 -> bits 10:1
    and edx, 0x000007FE
    or eax, edx

    ; imm[20] = inst[31] (sign bit)
    mov edx, r13d
    sar edx, 11                  ; Bit 31 -> bit 20
    and edx, 0x00100000
    or eax, edx

    ; Sign-extend from bit 20
    shl eax, 11
    sar eax, 11

    ret

;==============================================================================
; extract_b_type - B-type instruction format (branches)
; Input:  R13D = instruction
; Output: ECX = rs2, EBX = rs1, EAX = immediate (sign-extended, scaled by 2)
;
; B-type immediate: imm[12|10:5] rs2 rs1 funct3 imm[4:1|11] opcode
; Final imm = {inst[31], inst[7], inst[30:25], inst[11:8], 0}
;==============================================================================
extract_b_type:
    ; rs1 = bits 19:15
    mov eax, r13d
    shr eax, 15
    and eax, 0x1F
    mov ebx, eax

    ; rs2 = bits 24:20
    mov eax, r13d
    shr eax, 20
    and eax, 0x1F
    mov ecx, eax

    ; Build the immediate
    xor eax, eax

    ; imm[4:1] = inst[11:8]
    mov edx, r13d
    shr edx, 7                   ; Bits 11:8 -> bits 4:1
    and edx, 0x0000001E
    or eax, edx

    ; imm[10:5] = inst[30:25]
    mov edx, r13d
    shr edx, 20                  ; Bits 30:25 -> bits 10:5
    and edx, 0x000007E0
    or eax, edx

    ; imm[11] = inst[7]
    mov edx, r13d
    shl edx, 4                   ; Bit 7 -> bit 11
    and edx, 0x00000800
    or eax, edx

    ; imm[12] = inst[31] (sign bit)
    mov edx, r13d
    sar edx, 19                  ; Bit 31 -> bit 12
    and edx, 0x00001000
    or eax, edx

    ; Sign-extend from bit 12
    shl eax, 19
    sar eax, 19

    ret

;==============================================================================
; init_block_cache
; Initialise the block cache - call once at startup
; Input:  none
; Output: none
; "Have you tried turning it off and on again?"
;==============================================================================
init_block_cache:
    push rbx
    push rcx
    push rdi                        ; Callee-saved on Windows

    ; Zero out the block cache (mark all entries invalid)
    lea rdi, [block_cache]
    mov rcx, BLOCK_CACHE_SIZE * BLOCK_ENTRY_SIZE / 8
    xor eax, eax
    rep stosq

    ; Initialise code buffer pointer to start of buffer
    lea rax, [code_buffer]
    mov [code_buf_ptr], rax

    pop rdi
    pop rcx
    pop rbx
    ret

;==============================================================================
; lookup_block
; Find a cached block by PC
; Input:  RDI = RISC-V PC to look up
; Output: RAX = pointer to block entry, or 0 if not found
;==============================================================================
lookup_block:
    push rbx

    ; Hash: PC & (BLOCK_CACHE_SIZE - 1) = PC & 0x3FF
    mov rax, rdi
    and eax, (BLOCK_CACHE_SIZE - 1)

    ; Calculate entry address: block_cache + (hash * BLOCK_ENTRY_SIZE)
    shl eax, 6                      ; * 64
    lea rbx, [block_cache]
    add rbx, rax

    ; Check if valid and PC matches
    cmp byte [rbx + BLOCK_VALID], 1
    jne .not_found

    cmp [rbx + BLOCK_START_PC], rdi
    jne .not_found

    ; Found it!
    mov rax, rbx
    pop rbx
    ret

.not_found:
    xor eax, eax
    pop rbx
    ret

;==============================================================================
; translate_block
; Translate a basic block starting at given PC
; Input:  RDI = start PC
;         RSI = pointer to RISC-V memory (guest memory)
; Output: RAX = pointer to block entry
;
; Translates instructions until a branch/jump, caches the result
;==============================================================================
translate_block:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov [rbp-8], rdi                ; Save start PC
    mov [rbp-16], rsi               ; Save guest memory pointer

    ; First, check if already cached
    call lookup_block
    test rax, rax
    jnz .already_cached

    ; Not cached - need to translate
    mov rdi, [rbp-8]                ; Restore start PC
    mov rsi, [rbp-16]               ; Restore guest memory

    ; Get a cache slot (hash the PC)
    mov rax, rdi
    and eax, (BLOCK_CACHE_SIZE - 1)
    shl eax, 6
    lea r15, [block_cache]
    add r15, rax                    ; R15 = cache entry pointer

    ; Allocate space in code buffer
    mov r12, [code_buf_ptr]         ; R12 = output pointer (start of this block)
    mov [r15 + BLOCK_CODE_PTR], r12

    ; Store start PC
    mov rax, [rbp-8]
    mov [r15 + BLOCK_START_PC], rax

    ; R13 = current PC, R14 = guest memory base
    mov r13, [rbp-8]
    mov r14, [rbp-16]

    ; R8 = instruction count (safety limit)
    xor r8d, r8d

.translate_loop:
    ; Safety: max 256 instructions per block
    cmp r8d, 256
    jge .end_block_fallthrough
    inc r8d

    ; Fetch instruction from guest memory at current PC
    mov eax, [r14 + r13]            ; Load 32-bit instruction
    mov [rbp-24], eax               ; Save instruction

    ; Check if this is a block-ending instruction BEFORE translating
    mov ecx, eax
    and ecx, 0x7F                   ; Extract opcode

    cmp ecx, RV_OP_JAL
    je .is_jal

    cmp ecx, RV_OP_JALR
    je .is_jalr

    cmp ecx, RV_OP_BRANCH
    je .is_branch

    ; Not a block-ender - translate normally
    mov edi, eax                    ; instruction
    mov rsi, r12                    ; output buffer
    call translate_instruction
    add r12, rax                    ; Advance output pointer

    ; Advance PC by 4
    add r13, 4
    jmp .translate_loop

.is_jal:
    ; JAL - unconditional jump
    ; First, emit code to store current PC to rv_pc
    ; Emit: mov qword [r15], current_pc
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0xC7      ; MOV r/m64, imm32
    mov byte [r12+2], 0x07      ; ModRM: [r15]
    mov [r12+3], r13d           ; Current PC (32-bit immediate)
    add r12, 7

    ; Now translate the JAL
    mov edi, [rbp-24]
    mov rsi, r12
    call translate_instruction
    add r12, rax

    ; Extract the target PC (PC + imm)
    mov edi, [rbp-24]
    push r13
    mov r13d, edi                   ; Temporarily set R13D for extract_j_type
    call extract_j_type             ; EAX = immediate
    pop r13

    add rax, r13                    ; target = current_pc + imm
    mov [r15 + BLOCK_NEXT_PC], rax
    mov dword [r15 + BLOCK_EXIT_TYPE], EXIT_JUMP
    jmp .finish_block

.is_jalr:
    ; JALR - indirect jump (we can't know target statically)
    ; First, emit code to store current PC to rv_pc
    ; Emit: mov qword [r15], current_pc
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0xC7      ; MOV r/m64, imm32
    mov byte [r12+2], 0x07      ; ModRM: [r15]
    mov [r12+3], r13d           ; Current PC (32-bit immediate)
    add r12, 7

    ; Now translate the JALR
    mov edi, [rbp-24]
    mov rsi, r12
    call translate_instruction
    add r12, rax

    mov dword [r15 + BLOCK_EXIT_TYPE], EXIT_INDIRECT
    mov qword [r15 + BLOCK_NEXT_PC], 0
    jmp .finish_block

.is_branch:
    ; Conditional branch
    ; First, emit code to store current PC to rv_pc
    ; Emit: mov qword [r15], current_pc
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0xC7      ; MOV r/m64, imm32
    mov byte [r12+2], 0x07      ; ModRM: [r15]
    mov [r12+3], r13d           ; Current PC (32-bit immediate)
    add r12, 7

    ; Now translate the branch
    mov edi, [rbp-24]
    mov rsi, r12
    call translate_instruction
    add r12, rax

    ; Extract branch target
    mov edi, [rbp-24]
    push r13
    mov r13d, edi
    call extract_b_type             ; ECX = rs1, EBX = rs2, EAX = imm
    pop r13

    ; Taken target = PC + imm
    add rax, r13
    mov [r15 + BLOCK_TAKEN_PC], rax

    ; Not-taken target = PC + 4
    lea rax, [r13 + 4]
    mov [r15 + BLOCK_NOT_TAKEN_PC], rax

    mov dword [r15 + BLOCK_EXIT_TYPE], EXIT_BRANCH
    jmp .finish_block

.end_block_fallthrough:
    ; Hit instruction limit - fall through to next instruction
    mov [r15 + BLOCK_NEXT_PC], r13
    mov dword [r15 + BLOCK_EXIT_TYPE], EXIT_JUMP

.finish_block:
    ; Emit block epilogue: RET to return to executor
    mov byte [r12], 0xC3
    inc r12

    ; Calculate and store code size
    mov rax, r12
    sub rax, [r15 + BLOCK_CODE_PTR]
    mov [r15 + BLOCK_CODE_SIZE], eax

    ; Update code buffer allocation pointer
    mov [code_buf_ptr], r12

    ; Mark entry as valid
    mov byte [r15 + BLOCK_VALID], 1

    ; Return pointer to block entry
    mov rax, r15

.already_cached:
    ; RAX already has block pointer
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    add rsp, 64
    pop rbp
    ret

;==============================================================================
; execute_blocks
; Main execution loop - runs blocks until a stopping condition
; Input:  RDI = starting PC
;         RSI = pointer to guest memory
;         RDX = pointer to rv_regs array
;         RCX = pointer to rv_pc
;         R8  = max blocks to execute (0 = unlimited)
; Output: RAX = final PC value
;
; "Round and round the blocks we go, where we stop, nobody knows"
;==============================================================================
execute_blocks:
    push rbp
    mov rbp, rsp
    sub rsp, 80
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Save parameters
    mov [rbp-8], rdi            ; start PC
    mov [rbp-16], rsi           ; guest memory
    mov [rbp-24], rdx           ; rv_regs
    mov [rbp-32], rcx           ; rv_pc pointer
    mov [rbp-40], r8            ; max blocks

    ; Set initial PC
    mov rax, rdi
    mov rcx, [rbp-32]
    mov [rcx], rax

    ; R12 = block count
    xor r12d, r12d

.exec_loop:
    ; Check block limit
    mov rax, [rbp-40]
    test rax, rax
    jz .no_limit
    cmp r12, rax
    jge .done
.no_limit:
    inc r12

    ; Get current PC
    mov rcx, [rbp-32]
    mov rdi, [rcx]              ; RDI = current PC

    ; Translate/lookup block
    mov rsi, [rbp-16]           ; guest memory
    call translate_block
    test rax, rax
    jz .done                    ; No block = stop

    mov [rbp-48], rax           ; Save block pointer

    ; Set up execution state
    mov rbx, [rbp-24]           ; RBX = rv_regs
    mov r15, [rbp-32]           ; R15 = rv_pc pointer
    mov r14, [rbp-16]           ; R14 = guest memory (for loads/stores)

    ; Get code pointer and execute
    mov rax, [rbp-48]
    mov rax, [rax + BLOCK_CODE_PTR]
    call rax

    ; Block executed, PC has been updated
    ; Check if we should continue (indirect jumps return 0 in next_pc)
    mov rax, [rbp-48]
    cmp dword [rax + BLOCK_EXIT_TYPE], EXIT_INDIRECT
    je .check_indirect

    ; For direct jumps/branches, continue
    jmp .exec_loop

.check_indirect:
    ; For indirect jumps, PC is already set by the block
    ; Continue execution from new PC
    jmp .exec_loop

.done:
    ; Return final PC
    mov rcx, [rbp-32]
    mov rax, [rcx]

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    add rsp, 80
    pop rbp
    ret

;==============================================================================
; link_block
; Patch a block's exit to jump directly to another block
; Input:  RDI = source block pointer
;         RSI = slot (0 = primary/taken, 1 = not-taken)
;         RDX = target block pointer
; Output: RAX = 1 if linked, 0 if failed
;
; This patches the RET at the end of the block with a JMP to the target.
; Note: Current implementation uses RET, so this is for future optimization.
;==============================================================================
link_block:
    ; For now, just record the link in the block entry
    ; Future: actually patch the code

    test rsi, rsi
    jnz .link_not_taken

.link_taken:
    ; Store taken link
    mov [rdi + BLOCK_TAKEN_PC], rdx
    mov eax, 1
    ret

.link_not_taken:
    ; Store not-taken link
    mov [rdi + BLOCK_NOT_TAKEN_PC], rdx
    mov eax, 1
    ret
