; Conway - RISC-V to x86-64 Binary Translator
; decode.asm - RISC-V instruction decoder
;
; Decodes RV64I instructions into a structured format for dispatch

%include "rv_opcodes.inc"

section .data

section .bss
    ; Decoded instruction structure
    ; Offset 0:  opcode (8 bits)
    ; Offset 1:  rd (5 bits)
    ; Offset 2:  rs1 (5 bits)
    ; Offset 3:  rs2 (5 bits)
    ; Offset 4:  funct3 (3 bits)
    ; Offset 5:  funct7 (7 bits)
    ; Offset 8:  immediate (64 bits, sign-extended)
    ; Offset 16: instruction type (R/I/S/B/U/J)
    decoded_instr resb 24

section .text
    global decode_instruction
    global get_opcode
    global get_rd
    global get_rs1
    global get_rs2
    global get_funct3
    global get_funct7
    global get_immediate

; decode_instruction - Decode a 32-bit RISC-V instruction
; Input: edi = 32-bit instruction
; Output: rax = pointer to decoded instruction structure
decode_instruction:
    push rbp
    mov rbp, rsp
    push rbx

    mov ebx, edi                ; Save instruction

    ; Extract opcode (bits 6:0)
    mov eax, ebx
    and eax, 0x7F
    lea rcx, [rel decoded_instr]
    mov [rcx], al

    ; Determine instruction type and decode accordingly
    cmp al, RV_OP_LUI
    je .decode_u_type
    cmp al, RV_OP_AUIPC
    je .decode_u_type
    cmp al, RV_OP_JAL
    je .decode_j_type
    cmp al, RV_OP_JALR
    je .decode_i_type
    cmp al, RV_OP_BRANCH
    je .decode_b_type
    cmp al, RV_OP_LOAD
    je .decode_i_type
    cmp al, RV_OP_STORE
    je .decode_s_type
    cmp al, RV_OP_OP_IMM
    je .decode_i_type
    cmp al, RV_OP_OP
    je .decode_r_type
    cmp al, RV_OP_OP_IMM_32
    je .decode_i_type
    cmp al, RV_OP_OP_32
    je .decode_r_type

    ; Unknown opcode - treat as R-type
    jmp .decode_r_type

.decode_r_type:
    ; R-type: funct7 | rs2 | rs1 | funct3 | rd | opcode
    mov byte [rcx+16], INSTR_TYPE_R

    ; rd (bits 11:7)
    mov eax, ebx
    shr eax, 7
    and eax, 0x1F
    mov [rcx+1], al

    ; funct3 (bits 14:12)
    mov eax, ebx
    shr eax, 12
    and eax, 0x07
    mov [rcx+4], al

    ; rs1 (bits 19:15)
    mov eax, ebx
    shr eax, 15
    and eax, 0x1F
    mov [rcx+2], al

    ; rs2 (bits 24:20)
    mov eax, ebx
    shr eax, 20
    and eax, 0x1F
    mov [rcx+3], al

    ; funct7 (bits 31:25)
    mov eax, ebx
    shr eax, 25
    and eax, 0x7F
    mov [rcx+5], al

    ; No immediate for R-type
    mov qword [rcx+8], 0
    jmp .done

.decode_i_type:
    ; I-type: imm[11:0] | rs1 | funct3 | rd | opcode
    mov byte [rcx+16], INSTR_TYPE_I

    ; rd (bits 11:7)
    mov eax, ebx
    shr eax, 7
    and eax, 0x1F
    mov [rcx+1], al

    ; funct3 (bits 14:12)
    mov eax, ebx
    shr eax, 12
    and eax, 0x07
    mov [rcx+4], al

    ; rs1 (bits 19:15)
    mov eax, ebx
    shr eax, 15
    and eax, 0x1F
    mov [rcx+2], al

    ; rs2 not used
    mov byte [rcx+3], 0

    ; funct7 for shift instructions
    mov eax, ebx
    shr eax, 25
    and eax, 0x7F
    mov [rcx+5], al

    ; Immediate (bits 31:20, sign-extended)
    mov eax, ebx
    sar eax, 20                 ; Arithmetic shift for sign extension
    movsxd rax, eax
    mov [rcx+8], rax
    jmp .done

.decode_s_type:
    ; S-type: imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode
    mov byte [rcx+16], INSTR_TYPE_S

    ; rd not used
    mov byte [rcx+1], 0

    ; funct3 (bits 14:12)
    mov eax, ebx
    shr eax, 12
    and eax, 0x07
    mov [rcx+4], al

    ; rs1 (bits 19:15)
    mov eax, ebx
    shr eax, 15
    and eax, 0x1F
    mov [rcx+2], al

    ; rs2 (bits 24:20)
    mov eax, ebx
    shr eax, 20
    and eax, 0x1F
    mov [rcx+3], al

    ; Immediate: imm[4:0] from bits 11:7, imm[11:5] from bits 31:25
    mov eax, ebx
    shr eax, 7
    and eax, 0x1F               ; imm[4:0]
    mov edx, ebx
    sar edx, 20
    and edx, 0xFFFFFFE0         ; imm[11:5] in position
    or eax, edx
    movsxd rax, eax
    mov [rcx+8], rax
    jmp .done

.decode_b_type:
    ; B-type: imm[12|10:5] | rs2 | rs1 | funct3 | imm[4:1|11] | opcode
    mov byte [rcx+16], INSTR_TYPE_B

    ; rd not used
    mov byte [rcx+1], 0

    ; funct3 (bits 14:12)
    mov eax, ebx
    shr eax, 12
    and eax, 0x07
    mov [rcx+4], al

    ; rs1 (bits 19:15)
    mov eax, ebx
    shr eax, 15
    and eax, 0x1F
    mov [rcx+2], al

    ; rs2 (bits 24:20)
    mov eax, ebx
    shr eax, 20
    and eax, 0x1F
    mov [rcx+3], al

    ; Immediate reconstruction for B-type
    ; imm[11] from bit 7
    ; imm[4:1] from bits 11:8
    ; imm[10:5] from bits 30:25
    ; imm[12] from bit 31
    xor eax, eax

    mov edx, ebx
    shr edx, 7
    and edx, 1
    shl edx, 11                 ; imm[11]
    or eax, edx

    mov edx, ebx
    shr edx, 8
    and edx, 0x0F
    shl edx, 1                  ; imm[4:1]
    or eax, edx

    mov edx, ebx
    shr edx, 25
    and edx, 0x3F
    shl edx, 5                  ; imm[10:5]
    or eax, edx

    mov edx, ebx
    sar edx, 31                 ; Sign bit
    shl edx, 12                 ; imm[12]
    or eax, edx

    movsxd rax, eax
    mov [rcx+8], rax
    jmp .done

.decode_u_type:
    ; U-type: imm[31:12] | rd | opcode
    mov byte [rcx+16], INSTR_TYPE_U

    ; rd (bits 11:7)
    mov eax, ebx
    shr eax, 7
    and eax, 0x1F
    mov [rcx+1], al

    ; No rs1, rs2, funct3, funct7
    mov byte [rcx+2], 0
    mov byte [rcx+3], 0
    mov byte [rcx+4], 0
    mov byte [rcx+5], 0

    ; Immediate (bits 31:12, already in upper position)
    mov eax, ebx
    and eax, 0xFFFFF000
    movsxd rax, eax
    mov [rcx+8], rax
    jmp .done

.decode_j_type:
    ; J-type: imm[20|10:1|11|19:12] | rd | opcode
    mov byte [rcx+16], INSTR_TYPE_J

    ; rd (bits 11:7)
    mov eax, ebx
    shr eax, 7
    and eax, 0x1F
    mov [rcx+1], al

    ; No rs1, rs2, funct3, funct7
    mov byte [rcx+2], 0
    mov byte [rcx+3], 0
    mov byte [rcx+4], 0
    mov byte [rcx+5], 0

    ; Immediate reconstruction for J-type
    ; imm[19:12] from bits 19:12
    ; imm[11] from bit 20
    ; imm[10:1] from bits 30:21
    ; imm[20] from bit 31
    xor eax, eax

    mov edx, ebx
    and edx, 0x000FF000         ; imm[19:12]
    or eax, edx

    mov edx, ebx
    shr edx, 9
    and edx, 0x800              ; imm[11]
    or eax, edx

    mov edx, ebx
    shr edx, 20
    and edx, 0x7FE              ; imm[10:1]
    or eax, edx

    mov edx, ebx
    sar edx, 11
    and edx, 0x100000           ; imm[20] with sign
    or eax, edx

    movsxd rax, eax
    mov [rcx+8], rax
    jmp .done

.done:
    lea rax, [rel decoded_instr]
    pop rbx
    pop rbp
    ret

; Accessor functions for decoded instruction fields
get_opcode:
    lea rax, [rel decoded_instr]
    movzx eax, byte [rax]
    ret

get_rd:
    lea rax, [rel decoded_instr]
    movzx eax, byte [rax+1]
    ret

get_rs1:
    lea rax, [rel decoded_instr]
    movzx eax, byte [rax+2]
    ret

get_rs2:
    lea rax, [rel decoded_instr]
    movzx eax, byte [rax+3]
    ret

get_funct3:
    lea rax, [rel decoded_instr]
    movzx eax, byte [rax+4]
    ret

get_funct7:
    lea rax, [rel decoded_instr]
    movzx eax, byte [rax+5]
    ret

get_immediate:
    lea rax, [rel decoded_instr]
    mov rax, [rax+8]
    ret
