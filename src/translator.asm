; translator.asm
; Conway translator - library version (no main)
; Just the translate_instruction function for linking with test harnesses

bits 64
default rel

; External Windows API functions
extern Sleep
extern GetStdHandle
extern WriteFile
extern CreateFileA
extern ReadFile
extern CloseHandle
extern SetFilePointer
extern ExitProcess

; Windows file I/O constants
GENERIC_READ            equ 0x80000000
FILE_SHARE_READ         equ 1
OPEN_EXISTING           equ 3
FILE_ATTRIBUTE_NORMAL   equ 0x80
INVALID_HANDLE_VALUE    equ -1
FILE_BEGIN              equ 0
FILE_CURRENT            equ 1
FILE_END                equ 2

; File table constants
MAX_OPEN_FILES          equ 16
FD_OFFSET               equ 3       ; First allocatable fd (0,1,2 reserved)

;==============================================================================
; Constants
;==============================================================================

; RISC-V opcodes
RV_OP_LUI       equ 0x37
RV_OP_AUIPC     equ 0x17
RV_OP_OP_IMM    equ 0x13
RV_OP_OP_IMM_32 equ 0x1B        ; 32-bit immediate ops (addiw, slliw, etc.)
RV_OP_OP        equ 0x33
RV_OP_OP_32     equ 0x3B        ; 32-bit register ops (addw, subw, etc.)
RV_OP_LOAD      equ 0x03
RV_OP_STORE     equ 0x23
RV_OP_JAL       equ 0x6F        ; Jump and Link
RV_OP_JALR      equ 0x67        ; Jump and Link Register
RV_OP_BRANCH    equ 0x63        ; Conditional branches
RV_OP_SYSTEM    equ 0x73        ; ECALL, EBREAK, CSR instructions
RV_OP_MISC_MEM  equ 0x0F        ; FENCE, FENCE.I

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

; Funct3 for SYSTEM (CSR instructions)
RV_F3_PRIV      equ 0x0         ; ECALL, EBREAK, etc.
RV_F3_CSRRW     equ 0x1         ; CSR Read/Write
RV_F3_CSRRS     equ 0x2         ; CSR Read/Set
RV_F3_CSRRC     equ 0x3         ; CSR Read/Clear
RV_F3_CSRRWI    equ 0x5         ; CSR Read/Write Immediate
RV_F3_CSRRSI    equ 0x6         ; CSR Read/Set Immediate
RV_F3_CSRRCI    equ 0x7         ; CSR Read/Clear Immediate

; SYSTEM instruction immediate values (bits 31:20)
RV_SYS_ECALL    equ 0x000       ; Environment call
RV_SYS_EBREAK   equ 0x001       ; Breakpoint

section .data
    msg_exit        db "Exit: ", 0
    msg_done_debug  db "DONE", 13, 10, 0
    msg_syscall     db "Syscall: ", 0
    msg_newline     db 13, 10, 0

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
CODE_BUFFER_SIZE    equ 16777216        ; 16MB code buffer (Doom needs space!)

; Block entry offsets
BLOCK_VALID         equ 0               ; 1 byte: is entry valid?
BLOCK_START_PC      equ 8               ; 8 bytes: RISC-V start PC
BLOCK_CODE_PTR      equ 16              ; 8 bytes: pointer to x86 code
BLOCK_CODE_SIZE     equ 24              ; 4 bytes: size of x86 code
BLOCK_EXIT_TYPE     equ 28              ; 4 bytes: how block exits
BLOCK_NEXT_PC       equ 32              ; 8 bytes: unconditional target
BLOCK_TAKEN_PC      equ 40              ; 8 bytes: branch taken target
BLOCK_NOT_TAKEN_PC  equ 48              ; 8 bytes: branch not-taken target
BLOCK_LINK_ADDR     equ 56              ; 8 bytes: address of jmp instruction for linking

; Exit types
EXIT_NONE           equ 0               ; Block doesn't exit (incomplete)
EXIT_JUMP           equ 1               ; Unconditional jump (JAL/JALR)
EXIT_BRANCH         equ 2               ; Conditional branch
EXIT_INDIRECT       equ 3               ; Indirect jump (JALR with register)
EXIT_ECALL          equ 4               ; System call (needs handler)

section .bss
    alignb 4096
    block_cache:    resb BLOCK_CACHE_SIZE * BLOCK_ENTRY_SIZE    ; 64KB cache
    code_buffer:    resb CODE_BUFFER_SIZE                        ; 16MB code
    global code_buf_ptr
    code_buf_ptr:   resq 1                                       ; Allocation pointer
    ecall_pending:  resb 1                                       ; Set by ECALL blocks at runtime
    alignb 8
    stdout_handle:  resq 1                                       ; Windows stdout handle
    bytes_written:  resq 1                                       ; Temp for WriteFile
    bytes_read_tmp: resq 1                                       ; Temp for ReadFile
    file_table:     resq MAX_OPEN_FILES                          ; fd -> Windows HANDLE
    path_buffer:    resb 260                                     ; MAX_PATH for filename conversion
    num_buffer:     resb 16                                      ; Temp for number conversion
    global debug_block_count
    debug_block_count: resq 1                                    ; Debug: block counter
    global debug_last_pc
    debug_last_pc:  resq 1                                       ; Debug: last PC before crash

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

    cmp eax, RV_OP_OP_IMM_32
    je .op_imm_32

    cmp eax, RV_OP_OP
    je .op_reg

    cmp eax, RV_OP_OP_32
    je .op_reg_32

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

    cmp eax, RV_OP_SYSTEM
    je .system

    cmp eax, RV_OP_MISC_MEM
    je .fence

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

    push rax                    ; Save immediate (emit_load_rs1 clobbers EAX)
    call emit_load_rs1
    pop rax                     ; Restore immediate

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
    push rax                    ; Save immediate
    call emit_load_rs1
    pop rax                     ; Restore immediate

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
    push rax                    ; Save immediate
    call emit_load_rs1
    pop rax                     ; Restore immediate

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
    push rax                    ; Save immediate
    call emit_load_rs1
    pop rax                     ; Restore immediate

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
    push rcx                    ; Save rd
    push rax                    ; Save shamt
    call emit_load_rs1
    pop rcx                     ; Restore shamt to cl

    mov byte [r12], 0x48
    mov byte [r12+1], 0xC1
    mov byte [r12+2], 0xE0
    mov [r12+3], cl
    add r12, 4

    pop rcx                     ; Restore rd
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
; OP-IMM-32 (32-bit immediate operations)
; addiw, slliw, srliw, sraiw
; These operate on 32-bit values and sign-extend the result to 64-bit
;==============================================================================
.op_imm_32:
    call extract_i_type
    ; ECX = rd, EBX = rs1, EAX = imm12 (sign-extended)

    push rcx                    ; Save rd
    push rax                    ; Save imm12

    test ebx, ebx               ; Test rs1
    jnz .op_imm_32_load_rs1

    ; rs1 is x0, just use 0
    ; xor eax, eax
    mov byte [r12], 0x31
    mov byte [r12+1], 0xC0
    add r12, 2
    jmp .op_imm_32_dispatch

.op_imm_32_load_rs1:
    ; Load rs1 into RAX (then we use lower 32 bits via EAX)
    ; EBX already has rs1 from extract_i_type
    call emit_load_rs1

.op_imm_32_dispatch:
    ; Get funct3
    mov eax, r13d
    shr eax, 12
    and eax, 0x7

    cmp eax, RV_F3_ADDI
    je .addiw
    cmp eax, RV_F3_SLLI
    je .slliw
    cmp eax, RV_F3_SRLI_SRAI
    je .srxiw

    ; Unknown funct3 - treat as NOP
    pop rdx
    pop rcx
    jmp .emit_nop

.addiw:
    ; add eax, imm32
    pop rdx                     ; Restore imm12
    mov ecx, edx                ; imm12 already sign-extended
    cmp ecx, -128
    jl .addiw_32bit
    cmp ecx, 127
    jg .addiw_32bit

    ; 8-bit immediate: add eax, imm8
    mov byte [r12], 0x83
    mov byte [r12+1], 0xC0
    mov [r12+2], cl
    add r12, 3
    jmp .addiw_signext

.addiw_32bit:
    ; 32-bit immediate: add eax, imm32
    mov byte [r12], 0x05
    mov [r12+1], ecx
    add r12, 5

.addiw_signext:
    ; Sign-extend eax to rax: movsxd rax, eax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3
    jmp .op_imm_32_store

.slliw:
    ; shl eax, shamt (shamt in bits 24:20)
    pop rdx                     ; Pop imm (not used for shifts, shamt is in instruction)
    mov ecx, r13d
    shr ecx, 20
    and ecx, 0x1F
    mov byte [r12], 0xC1
    mov byte [r12+1], 0xE0
    mov [r12+2], cl
    add r12, 3
    jmp .addiw_signext          ; Sign-extend after shift

.srxiw:
    pop rdx                     ; Pop imm (not used)
    ; Check funct7 bit to distinguish srliw/sraiw
    mov eax, r13d
    shr eax, 30
    and eax, 1

    mov ecx, r13d
    shr ecx, 20
    and ecx, 0x1F               ; shamt

    test ebx, ebx               ; Test rs1
    jnz .sraiw

    ; srliw: shr eax, shamt
    mov byte [r12], 0xC1
    mov byte [r12+1], 0xE8
    mov [r12+2], cl
    add r12, 3
    jmp .addiw_signext

.sraiw:
    ; sraiw: sar eax, shamt
    mov byte [r12], 0xC1
    mov byte [r12+1], 0xF8
    mov [r12+2], cl
    add r12, 3
    jmp .addiw_signext

.op_imm_32_store:
    pop rcx                     ; Restore rd
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

    ; Check for M extension (funct7 = 0x01)
    cmp r15d, 0x01
    je .m_extension

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
; M Extension (funct7 = 0x01): MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
;==============================================================================
.m_extension:
    ; EAX = funct3 (0-7 determines operation)
    cmp eax, 0
    je .mul
    cmp eax, 1
    je .mulh
    cmp eax, 2
    je .mulhsu
    cmp eax, 3
    je .mulhu
    cmp eax, 4
    je .div
    cmp eax, 5
    je .divu
    cmp eax, 6
    je .rem
    cmp eax, 7
    je .remu

    mov byte [r12], 0xCC        ; Unknown M-extension op
    mov rax, 1
    jmp .done

;------------------------------------------------------------------------------
; MUL: rd = (rs1 * rs2)[63:0]
;------------------------------------------------------------------------------
.mul:
    call extract_r_type
    test ecx, ecx
    jz .emit_nop

    ; Load rs1 into RAX
    push rcx
    push rax
    mov ecx, ebx                ; rs1
    call emit_load_reg_to_rax
    pop rax

    ; Load rs2 into RCX
    push rax
    mov ecx, eax                ; rs2
    call emit_load_reg_to_rcx
    pop rax
    pop rcx

    ; Emit: imul rax, rcx (signed multiply, low 64 bits)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xAF
    mov byte [r12+3], 0xC1      ; ModRM: rax, rcx
    add r12, 4

    ; Store RAX to rd
    call emit_store_rax_to_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; MULH: rd = (signed(rs1) * signed(rs2))[127:64]
;------------------------------------------------------------------------------
.mulh:
    call extract_r_type
    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax

    ; Load rs1 into RAX
    mov ecx, ebx
    call emit_load_reg_to_rax

    ; Load rs2 into RCX
    mov eax, [rsp]
    mov ecx, eax
    call emit_load_reg_to_rcx

    ; Emit: imul rcx (signed multiply RAX*RCX -> RDX:RAX)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xF7
    mov byte [r12+2], 0xE9      ; ModRM: imul rcx
    add r12, 3

    ; Result high bits in RDX, move to RAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xD0      ; mov rax, rdx
    add r12, 3

    pop rax
    pop rcx
    call emit_store_rax_to_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; MULHSU: rd = (signed(rs1) * unsigned(rs2))[127:64]
; This is tricky - x86 doesn't have mixed-sign multiply
;------------------------------------------------------------------------------
.mulhsu:
    ; For now, treat as unsigned (not perfectly correct but functional)
    jmp .mulhu

;------------------------------------------------------------------------------
; MULHU: rd = (unsigned(rs1) * unsigned(rs2))[127:64]
;------------------------------------------------------------------------------
.mulhu:
    call extract_r_type
    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax

    ; Load rs1 into RAX
    mov ecx, ebx
    call emit_load_reg_to_rax

    ; Load rs2 into RCX
    mov eax, [rsp]
    mov ecx, eax
    call emit_load_reg_to_rcx

    ; Emit: mul rcx (unsigned multiply RAX*RCX -> RDX:RAX)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xF7
    mov byte [r12+2], 0xE1      ; ModRM: mul rcx
    add r12, 3

    ; Result high bits in RDX, move to RAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xD0      ; mov rax, rdx
    add r12, 3

    pop rax
    pop rcx
    call emit_store_rax_to_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; DIV: rd = signed(rs1) / signed(rs2)
;------------------------------------------------------------------------------
.div:
    call extract_r_type
    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax

    ; Load rs1 into RAX
    mov ecx, ebx
    call emit_load_reg_to_rax

    ; Sign-extend RAX into RDX:RAX (cqo)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x99      ; cqo
    add r12, 2

    ; Load rs2 into RCX
    mov eax, [rsp]
    mov ecx, eax
    call emit_load_reg_to_rcx

    ; RISC-V: signed division by zero returns -1
    ; Emit: test rcx, rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x85
    mov byte [r12+2], 0xC9      ; test rcx, rcx
    add r12, 3

    ; Emit: jnz +9 (skip mov rax,-1 + jmp)
    mov byte [r12], 0x75        ; jnz rel8
    mov byte [r12+1], 9         ; skip 9 bytes
    add r12, 2

    ; Emit: mov rax, -1 (RISC-V div-by-zero result)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC0      ; mov rax, imm32 (sign-extended)
    mov dword [r12+3], 0xFFFFFFFF
    add r12, 7

    ; Emit: jmp +3 (skip idiv rcx)
    mov byte [r12], 0xEB        ; jmp rel8
    mov byte [r12+1], 3         ; skip 3 bytes
    add r12, 2

    ; Emit: idiv rcx (signed divide RDX:RAX / RCX -> RAX=quotient, RDX=remainder)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xF7
    mov byte [r12+2], 0xF9      ; ModRM: idiv rcx
    add r12, 3

    pop rax
    pop rcx
    call emit_store_rax_to_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; DIVU: rd = unsigned(rs1) / unsigned(rs2)
;------------------------------------------------------------------------------
.divu:
    call extract_r_type
    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax

    ; Load rs1 into RAX
    mov ecx, ebx
    call emit_load_reg_to_rax

    ; Zero-extend RAX into RDX:RAX (xor rdx, rdx)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x31
    mov byte [r12+2], 0xD2      ; xor rdx, rdx
    add r12, 3

    ; Load rs2 into RCX
    mov eax, [rsp]
    mov ecx, eax
    call emit_load_reg_to_rcx

    ; RISC-V: division by zero returns all 1s
    ; Emit: test rcx, rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x85
    mov byte [r12+2], 0xC9      ; test rcx, rcx
    add r12, 3

    ; Emit: jnz +5 (skip over mov rax, -1 which is 7 bytes? No, let's use jnz +10 to skip mov rax,-1 + jmp)
    ; Actually: jnz .do_div (skip mov rax,-1 and jmp .done)
    ; mov rax, -1 is 10 bytes: 48 C7 C0 FF FF FF FF (mov eax,-1 sign-ext) or 48 B8 ... (movabs)
    ; Let's use: mov rax, -1 → 48 C7 C0 FF FF FF FF (7 bytes, sign-extended)
    ; jmp .done → EB 03 (2 bytes, skip div rcx which is 3 bytes)
    ; Total to skip: 7 + 2 = 9 bytes
    mov byte [r12], 0x75        ; jnz rel8
    mov byte [r12+1], 9         ; skip 9 bytes (mov rax,-1 + jmp)
    add r12, 2

    ; Emit: mov rax, -1 (RISC-V div-by-zero result)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC0      ; mov rax, imm32 (sign-extended)
    mov dword [r12+3], 0xFFFFFFFF
    add r12, 7

    ; Emit: jmp +3 (skip div rcx)
    mov byte [r12], 0xEB        ; jmp rel8
    mov byte [r12+1], 3         ; skip 3 bytes (div rcx)
    add r12, 2

    ; Emit: div rcx (unsigned divide RDX:RAX / RCX -> RAX=quotient, RDX=remainder)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xF7
    mov byte [r12+2], 0xF1      ; ModRM: div rcx
    add r12, 3

    pop rax
    pop rcx
    call emit_store_rax_to_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; REM: rd = signed(rs1) % signed(rs2)
; RISC-V: remainder by zero returns dividend (rs1)
;------------------------------------------------------------------------------
.rem:
    call extract_r_type
    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax

    ; Load rs1 into RAX
    mov ecx, ebx
    call emit_load_reg_to_rax

    ; Sign-extend RAX into RDX:RAX (cqo)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x99
    add r12, 2

    ; Load rs2 into RCX
    mov eax, [rsp]
    mov ecx, eax
    call emit_load_reg_to_rcx

    ; Check for zero divisor
    ; Emit: test rcx, rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x85
    mov byte [r12+2], 0xC9
    add r12, 3

    ; Emit: jz +6 (skip idiv + mov rdx to rax = 3 + 3 bytes)
    mov byte [r12], 0x74        ; jz rel8
    mov byte [r12+1], 6         ; skip 6 bytes
    add r12, 2

    ; Emit: idiv rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0xF7
    mov byte [r12+2], 0xF9
    add r12, 3

    ; Remainder is in RDX, move to RAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xD0      ; mov rax, rdx
    add r12, 3

    ; If divisor was zero, RAX still has rs1 (dividend) which is correct

    pop rax
    pop rcx
    call emit_store_rax_to_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; REMU: rd = unsigned(rs1) % unsigned(rs2)
; RISC-V: remainder by zero returns dividend (rs1)
;------------------------------------------------------------------------------
.remu:
    call extract_r_type
    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax

    ; Load rs1 into RAX
    mov ecx, ebx
    call emit_load_reg_to_rax

    ; Zero-extend RAX into RDX:RAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x31
    mov byte [r12+2], 0xD2      ; xor rdx, rdx
    add r12, 3

    ; Load rs2 into RCX
    mov eax, [rsp]
    mov ecx, eax
    call emit_load_reg_to_rcx

    ; Check for zero divisor
    ; Emit: test rcx, rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x85
    mov byte [r12+2], 0xC9
    add r12, 3

    ; Emit: jz +6 (skip div + mov rdx to rax = 3 + 3 bytes)
    mov byte [r12], 0x74        ; jz rel8
    mov byte [r12+1], 6         ; skip 6 bytes
    add r12, 2

    ; Emit: div rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0xF7
    mov byte [r12+2], 0xF1
    add r12, 3

    ; Remainder is in RDX, move to RAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xD0      ; mov rax, rdx
    add r12, 3

    ; If divisor was zero, RAX still has rs1 (dividend) which is correct

    pop rax
    pop rcx
    call emit_store_rax_to_rd
    jmp .calc_size

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
; OP-32 (32-bit register operations: addw, subw, sllw, srlw, sraw, etc.)
; Same as OP but result is sign-extended 32-bit
;==============================================================================
.op_reg_32:
    ; Extract funct3 and funct7
    mov eax, r13d
    shr eax, 12
    and eax, 0x7                ; funct3

    mov ecx, r13d
    shr ecx, 25                 ; funct7

    ; Dispatch based on funct3 and funct7
    cmp eax, 0                  ; addw/subw/mulw
    jne .op32_check_sll
    cmp ecx, 0
    je .addw
    cmp ecx, 0x20
    je .subw
    cmp ecx, 1
    je .mulw
    jmp .op32_unsupported

.op32_check_sll:
    cmp eax, 1                  ; sllw
    jne .op32_check_srl
    cmp ecx, 0
    je .sllw
    jmp .op32_unsupported

.op32_check_srl:
    cmp eax, 5                  ; srlw/sraw/divuw
    jne .op32_check_div
    cmp ecx, 0
    je .srlw
    cmp ecx, 0x20
    je .sraw
    cmp ecx, 1
    je .divuw
    jmp .op32_unsupported

.op32_check_div:
    cmp eax, 4                  ; divw
    jne .op32_check_rem
    cmp ecx, 1
    je .divw
    jmp .op32_unsupported

.op32_check_rem:
    cmp eax, 6                  ; remw
    jne .op32_check_remu
    cmp ecx, 1
    je .remw
    jmp .op32_unsupported

.op32_check_remu:
    cmp eax, 7                  ; remuw
    jne .op32_unsupported
    cmp ecx, 1
    je .remuw

.op32_unsupported:
    mov byte [r12], 0xCC        ; INT3 for debugging
    mov rax, 1
    jmp .done

;------------------------------------------------------------------------------
; ADDW - Add word (32-bit, sign-extend result)
;------------------------------------------------------------------------------
.addw:
    call extract_r_type         ; ECX=rd, EBX=rs1, EDX=rs2

    test ecx, ecx
    jz .emit_nop

    push rcx                    ; Save rd
    call emit_load_rs1          ; EAX = rs1 value
    pop rcx

    ; Load rs2 to temp
    push rcx
    push rax
    mov ecx, edx                ; rs2
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x53      ; MOV RDX, [RBX + rs2*8]
    mov eax, ecx
    shl eax, 3
    mov [r12+3], al
    add r12, 4
    pop rax
    pop rcx

    ; ADD EAX, EDX (32-bit add)
    mov byte [r12], 0x01
    mov byte [r12+1], 0xD0      ; ADD EAX, EDX
    add r12, 2

    ; Sign-extend EAX to RAX: MOVSXD RAX, EAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    call emit_store_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; SUBW - Subtract word (32-bit, sign-extend result)
;------------------------------------------------------------------------------
.subw:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    call emit_load_rs1
    pop rcx

    push rcx
    push rax
    mov ecx, edx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x53
    mov eax, ecx
    shl eax, 3
    mov [r12+3], al
    add r12, 4
    pop rax
    pop rcx

    ; SUB EAX, EDX
    mov byte [r12], 0x29
    mov byte [r12+1], 0xD0
    add r12, 2

    ; MOVSXD RAX, EAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    call emit_store_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; SLLW - Shift left logical word
;------------------------------------------------------------------------------
.sllw:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rdx
    call emit_load_rs1          ; EAX = rs1
    pop rdx
    pop rcx

    ; Load rs2 to ECX (for shift amount)
    push rcx
    mov byte [r12], 0x8B
    mov byte [r12+1], 0x4B      ; MOV ECX, [RBX + rs2*8]
    mov eax, edx
    shl eax, 3
    mov [r12+2], al
    add r12, 3
    pop rcx

    ; SHL EAX, CL
    mov byte [r12], 0xD3
    mov byte [r12+1], 0xE0
    add r12, 2

    ; MOVSXD RAX, EAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    push rcx
    call emit_store_rd
    pop rcx
    jmp .calc_size

;------------------------------------------------------------------------------
; SRLW - Shift right logical word
;------------------------------------------------------------------------------
.srlw:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rdx
    call emit_load_rs1
    pop rdx
    pop rcx

    push rcx
    mov byte [r12], 0x8B
    mov byte [r12+1], 0x4B
    mov eax, edx
    shl eax, 3
    mov [r12+2], al
    add r12, 3
    pop rcx

    ; SHR EAX, CL
    mov byte [r12], 0xD3
    mov byte [r12+1], 0xE8
    add r12, 2

    ; MOVSXD RAX, EAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    push rcx
    call emit_store_rd
    pop rcx
    jmp .calc_size

;------------------------------------------------------------------------------
; SRAW - Shift right arithmetic word
;------------------------------------------------------------------------------
.sraw:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rdx
    call emit_load_rs1
    pop rdx
    pop rcx

    push rcx
    mov byte [r12], 0x8B
    mov byte [r12+1], 0x4B
    mov eax, edx
    shl eax, 3
    mov [r12+2], al
    add r12, 3
    pop rcx

    ; SAR EAX, CL
    mov byte [r12], 0xD3
    mov byte [r12+1], 0xF8
    add r12, 2

    ; MOVSXD RAX, EAX (already sign-extended by SAR on 32-bit)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    push rcx
    call emit_store_rd
    pop rcx
    jmp .calc_size

;------------------------------------------------------------------------------
; MULW - Multiply word (32-bit, sign-extend result)
;------------------------------------------------------------------------------
.mulw:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rdx
    call emit_load_rs1          ; EAX = rs1
    pop rdx
    pop rcx

    ; Load rs2 to EDX
    push rcx
    mov byte [r12], 0x8B
    mov byte [r12+1], 0x53
    mov eax, edx
    shl eax, 3
    mov [r12+2], al
    add r12, 3

    ; IMUL EAX, EDX (result in EAX, ignore overflow to EDX)
    mov byte [r12], 0x0F
    mov byte [r12+1], 0xAF
    mov byte [r12+2], 0xC2      ; IMUL EAX, EDX
    add r12, 3

    ; MOVSXD RAX, EAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; DIVW - Divide word (signed)
;------------------------------------------------------------------------------
.divw:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rdx
    call emit_load_rs1          ; EAX = rs1
    pop rdx
    pop rcx

    ; Sign-extend EAX to EDX:EAX using CDQ
    mov byte [r12], 0x99        ; CDQ
    add r12, 1

    ; Load rs2 to ECX
    push rcx
    mov byte [r12], 0x8B
    mov byte [r12+1], 0x4B
    mov eax, edx
    shl eax, 3
    mov [r12+2], al
    add r12, 3

    ; IDIV ECX (EAX = EDX:EAX / ECX)
    mov byte [r12], 0xF7
    mov byte [r12+1], 0xF9      ; IDIV ECX
    add r12, 2

    ; MOVSXD RAX, EAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; DIVUW - Divide word (unsigned)
;------------------------------------------------------------------------------
.divuw:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rdx
    call emit_load_rs1

    ; Zero-extend EAX to EDX:EAX
    mov byte [r12], 0x31
    mov byte [r12+1], 0xD2      ; XOR EDX, EDX
    add r12, 2

    pop rdx
    pop rcx

    push rcx
    mov byte [r12], 0x8B
    mov byte [r12+1], 0x4B
    mov eax, edx
    shl eax, 3
    mov [r12+2], al
    add r12, 3

    ; DIV ECX
    mov byte [r12], 0xF7
    mov byte [r12+1], 0xF1      ; DIV ECX
    add r12, 2

    ; MOVSXD RAX, EAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; REMW - Remainder word (signed)
;------------------------------------------------------------------------------
.remw:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rdx
    call emit_load_rs1

    ; CDQ
    mov byte [r12], 0x99
    add r12, 1

    pop rdx
    pop rcx

    push rcx
    mov byte [r12], 0x8B
    mov byte [r12+1], 0x4B
    mov eax, edx
    shl eax, 3
    mov [r12+2], al
    add r12, 3

    ; IDIV ECX
    mov byte [r12], 0xF7
    mov byte [r12+1], 0xF9
    add r12, 2

    ; MOV EAX, EDX (remainder is in EDX)
    mov byte [r12], 0x89
    mov byte [r12+1], 0xD0
    add r12, 2

    ; MOVSXD RAX, EAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; REMUW - Remainder word (unsigned)
;------------------------------------------------------------------------------
.remuw:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rdx
    call emit_load_rs1

    ; XOR EDX, EDX
    mov byte [r12], 0x31
    mov byte [r12+1], 0xD2
    add r12, 2

    pop rdx
    pop rcx

    push rcx
    mov byte [r12], 0x8B
    mov byte [r12+1], 0x4B
    mov eax, edx
    shl eax, 3
    mov [r12+2], al
    add r12, 3

    ; DIV ECX
    mov byte [r12], 0xF7
    mov byte [r12+1], 0xF1
    add r12, 2

    ; MOV EAX, EDX
    mov byte [r12], 0x89
    mov byte [r12+1], 0xD0
    add r12, 2

    ; MOVSXD RAX, EAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
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
    push rcx                    ; Save rs2

    ; Emit: mov rax, [rbx + rs1*8] - use emit_load_rs1 for proper disp32 handling
    call emit_load_rs1

    pop rcx                     ; Restore rs2

    ; Emit: mov rcx, [rbx + rs2*8]
    mov eax, ecx
    shl eax, 3
    cmp eax, 127
    jg .branch_rs2_disp32

    ; 8-bit displacement
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B      ; ModRM: rcx, [rbx + disp8]
    mov [r12+3], al
    add r12, 4
    jmp .branch_cmp

.branch_rs2_disp32:
    ; 32-bit displacement
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x8B      ; ModRM: rcx, [rbx + disp32]
    mov [r12+3], eax
    add r12, 7

.branch_cmp:
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
; SYSTEM (ECALL, EBREAK, CSR)
;==============================================================================
.system:
    ; Extract funct3
    mov eax, r13d
    shr eax, 12
    and eax, 0x7

    cmp eax, RV_F3_PRIV
    je .system_priv

    ; CSR instructions - dispatch by funct3
    cmp eax, RV_F3_CSRRW
    je .csrrw
    cmp eax, RV_F3_CSRRS
    je .csrrs
    cmp eax, RV_F3_CSRRC
    je .csrrc
    cmp eax, RV_F3_CSRRWI
    je .csrrwi
    cmp eax, RV_F3_CSRRSI
    je .csrrsi
    cmp eax, RV_F3_CSRRCI
    je .csrrci

    ; Unknown SYSTEM instruction
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

.system_priv:
    ; Check immediate field for ECALL vs EBREAK
    mov eax, r13d
    shr eax, 20
    and eax, 0xFFF

    cmp eax, RV_SYS_ECALL
    je .ecall
    cmp eax, RV_SYS_EBREAK
    je .ebreak

    ; Unknown privileged instruction - emit INT3
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

.ecall:
    ; ECALL - System call
    ; The syscall number is in a7 (x17), args in a0-a5 (x10-x15)
    ; We just return to the executor which will handle it
    ; First, update PC to point to next instruction (PC + 4)
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

    ; Emit: mov [r15], rax
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x07
    add r12, 3

    ; Emit code to set ecall_pending = 1 at runtime (for block linking)
    ; Emit: movabs rax, ecall_pending (48 B8 <8 bytes>)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xB8
    lea rax, [ecall_pending]
    mov [r12+2], rax
    add r12, 10

    ; Emit: mov byte [rax], 1 (C6 00 01)
    mov byte [r12], 0xC6
    mov byte [r12+1], 0x00
    mov byte [r12+2], 0x01
    add r12, 3

    ; Return - the executor will check ecall_pending flag
    jmp .calc_size

.ebreak:
    ; EBREAK - Debugger breakpoint
    ; Emit INT3 for debugging
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;==============================================================================
; CSR Instructions
; For now, we'll implement a simple stub that ignores writes and returns 0
; Real implementation would need a CSR array
;==============================================================================
.csrrw:
.csrrs:
.csrrc:
.csrrwi:
.csrrsi:
.csrrci:
    ; Extract rd
    mov eax, r13d
    shr eax, 7
    and eax, 0x1F

    ; If rd != 0, write 0 to it (stub implementation)
    test ebx, ebx               ; Test rs1
    jz .csr_done

    ; Emit: mov qword [rbx + rd*8], 0
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0x43
    shl eax, 3
    mov [r12+3], al
    mov dword [r12+4], 0
    add r12, 8

.csr_done:
    jmp .calc_size

;==============================================================================
; FENCE - Memory ordering (NOP on x86)
;==============================================================================
.fence:
    ; x86 has strong memory ordering, so FENCE is a NOP
    ; Just emit a NOP for clarity
    mov byte [r12], 0x90
    mov rax, 1
    jmp .done

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
; translate_compressed
; Translate a 16-bit compressed RISC-V instruction to x86-64
; Input:  DI = 16-bit compressed instruction
;         RSI = output buffer pointer
; Output: RAX = bytes written
;==============================================================================
translate_compressed:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rsi                ; r12 = output pointer
    movzx r13d, di              ; r13d = instruction
    mov r14, rsi                ; r14 = buffer start for size calc

    ; Extract quadrant (bits 1:0)
    mov eax, r13d
    and eax, 0x3

    cmp eax, 0x0
    je .c_quadrant0

    cmp eax, 0x1
    je .c_quadrant1

    cmp eax, 0x2
    je .c_quadrant2

    ; Unknown quadrant - emit INT3
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .c_done

;------------------------------------------------------------------------------
; Quadrant 0: C.ADDI4SPN, C.LW, C.LD, C.SW, C.SD, etc.
;------------------------------------------------------------------------------
.c_quadrant0:
    mov eax, r13d
    shr eax, 13
    and eax, 0x7                ; funct3

    cmp eax, 0                  ; C.ADDI4SPN
    je .c_addi4spn

    cmp eax, 2                  ; C.LW
    je .c_lw

    cmp eax, 3                  ; C.LD (RV64) or C.FLW (RV32)
    je .c_ld

    cmp eax, 6                  ; C.SW
    je .c_sw

    cmp eax, 7                  ; C.SD (RV64) or C.FSW (RV32)
    je .c_sd

    ; Unsupported Q0 instruction
    jmp .c_emit_nop

;------------------------------------------------------------------------------
; Quadrant 1: C.ADDI, C.LI, C.LUI, C.ADDI16SP, C.J, C.BEQZ, C.BNEZ, ALU ops
;------------------------------------------------------------------------------
.c_quadrant1:
    mov eax, r13d
    shr eax, 13
    and eax, 0x7                ; funct3

    cmp eax, 0                  ; C.NOP / C.ADDI
    je .c_addi

    cmp eax, 1                  ; C.ADDIW (RV64) / C.JAL (RV32)
    je .c_addiw

    cmp eax, 2                  ; C.LI
    je .c_li

    cmp eax, 3                  ; C.LUI / C.ADDI16SP
    je .c_lui_addi16sp

    cmp eax, 4                  ; C.SRLI / C.SRAI / C.ANDI / C.SUB / C.XOR / C.OR / C.AND
    je .c_alu

    cmp eax, 5                  ; C.J
    je .c_j_impl

    cmp eax, 6                  ; C.BEQZ
    je .c_beqz

    cmp eax, 7                  ; C.BNEZ
    je .c_bnez

    jmp .c_emit_nop

;------------------------------------------------------------------------------
; Quadrant 2: C.SLLI, C.LWSP, C.LDSP, C.JR, C.MV, C.ADD, C.SWSP, C.SDSP
;------------------------------------------------------------------------------
.c_quadrant2:
    mov eax, r13d
    shr eax, 13
    and eax, 0x7                ; funct3

    cmp eax, 0                  ; C.SLLI
    je .c_slli

    cmp eax, 2                  ; C.LWSP
    je .c_lwsp

    cmp eax, 3                  ; C.LDSP (RV64) / C.FLWSP (RV32)
    je .c_ldsp

    cmp eax, 4                  ; C.JR / C.MV / C.EBREAK / C.JALR / C.ADD
    je .c_cr_format

    cmp eax, 6                  ; C.SWSP
    je .c_swsp

    cmp eax, 7                  ; C.SDSP (RV64) / C.FSWSP (RV32)
    je .c_sdsp

    jmp .c_emit_nop

;==============================================================================
; C Extension instruction implementations
;==============================================================================

;------------------------------------------------------------------------------
; C.ADDI4SPN: addi rd', x2, nzuimm
; Format: CIW - rd' in bits 4:2, immediate in bits 12:5
;------------------------------------------------------------------------------
.c_addi4spn:
    ; rd' = bits 4:2 (maps to x8-x15)
    mov ecx, r13d
    shr ecx, 2
    and ecx, 0x7
    add ecx, 8                  ; rd = rd' + 8

    ; Extract immediate: nzuimm[5:4|9:6|2|3]
    ; imm[5:4] = inst[12:11], imm[9:6] = inst[10:7], imm[2] = inst[6], imm[3] = inst[5]
    xor eax, eax

    ; imm[5:4] from inst[12:11]
    mov edx, r13d
    shr edx, 11
    and edx, 0x3
    shl edx, 4
    or eax, edx

    ; imm[9:6] from inst[10:7]
    mov edx, r13d
    shr edx, 7
    and edx, 0xF
    shl edx, 6
    or eax, edx

    ; imm[2] from inst[6]
    mov edx, r13d
    shr edx, 6
    and edx, 0x1
    shl edx, 2
    or eax, edx

    ; imm[3] from inst[5]
    mov edx, r13d
    shr edx, 5
    and edx, 0x1
    shl edx, 3
    or eax, edx

    ; Load sp (x2) into RAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov byte [r12+3], 16        ; x2 * 8 = 16
    add r12, 4

    ; Add immediate
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], eax
    add r12, 6

    ; Store to rd
    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.LW: lw rd', offset(rs1')
;------------------------------------------------------------------------------
.c_lw:
    ; rd' = bits 4:2, rs1' = bits 9:7
    mov ecx, r13d
    shr ecx, 2
    and ecx, 0x7
    add ecx, 8                  ; rd

    mov ebx, r13d
    shr ebx, 7
    and ebx, 0x7
    add ebx, 8                  ; rs1

    ; offset[5:3] = inst[12:10], offset[2|6] = inst[6:5]
    xor eax, eax

    mov edx, r13d
    shr edx, 10
    and edx, 0x7
    shl edx, 3
    or eax, edx

    mov edx, r13d
    shr edx, 6
    and edx, 0x1
    shl edx, 2
    or eax, edx

    mov edx, r13d
    shr edx, 5
    and edx, 0x1
    shl edx, 6
    or eax, edx

    ; Load rs1 into RAX
    push rcx
    push rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rax
    pop rcx

    ; Add offset
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], eax
    add r12, 6

    ; Load 32-bit sign-extended from [r14+rax]
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0x63      ; MOVSXD
    mov byte [r12+2], 0x04      ; ModRM: SIB mode
    mov byte [r12+3], 0x06      ; SIB: base=r14, index=rax
    add r12, 4

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.LD: ld rd', offset(rs1')
;------------------------------------------------------------------------------
.c_ld:
    mov ecx, r13d
    shr ecx, 2
    and ecx, 0x7
    add ecx, 8                  ; rd

    mov ebx, r13d
    shr ebx, 7
    and ebx, 0x7
    add ebx, 8                  ; rs1

    ; offset[5:3] = inst[12:10], offset[7:6] = inst[6:5]
    xor eax, eax

    mov edx, r13d
    shr edx, 10
    and edx, 0x7
    shl edx, 3
    or eax, edx

    mov edx, r13d
    shr edx, 5
    and edx, 0x3
    shl edx, 6
    or eax, edx

    ; Load rs1
    push rcx
    push rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rax
    pop rcx

    ; Add offset
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], eax
    add r12, 6

    ; Load 64-bit from [r14+rax]
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0x8B      ; MOV
    mov byte [r12+2], 0x04      ; ModRM: SIB mode
    mov byte [r12+3], 0x06      ; SIB: base=r14, index=rax
    add r12, 4

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.SW: sw rs2', offset(rs1')
;------------------------------------------------------------------------------
.c_sw:
    ; rs2' = bits 4:2, rs1' = bits 9:7
    mov edx, r13d
    shr edx, 2
    and edx, 0x7
    add edx, 8                  ; rs2

    mov ebx, r13d
    shr ebx, 7
    and ebx, 0x7
    add ebx, 8                  ; rs1

    ; offset[5:3] = inst[12:10], offset[2|6] = inst[6:5]
    xor eax, eax

    mov ecx, r13d
    shr ecx, 10
    and ecx, 0x7
    shl ecx, 3
    or eax, ecx

    mov ecx, r13d
    shr ecx, 6
    and ecx, 0x1
    shl ecx, 2
    or eax, ecx

    mov ecx, r13d
    shr ecx, 5
    and ecx, 0x1
    shl ecx, 6
    or eax, ecx

    push rax                    ; Save offset
    push rdx                    ; Save rs2

    ; Load rs1 into RCX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B      ; mov rcx, [rbx + disp8]
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4

    pop rdx                     ; Restore rs2

    ; Load rs2 into EAX
    mov byte [r12], 0x8B
    mov byte [r12+1], 0x43
    mov eax, edx
    shl eax, 3
    mov byte [r12+2], al
    add r12, 3

    pop rdx                     ; Restore offset (into edx)

    ; Add offset to RCX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x81
    mov byte [r12+2], 0xC1      ; add rcx, imm32
    mov [r12+3], edx
    add r12, 7

    ; Store to [r14+rcx]: mov [r14+rcx], eax
    mov byte [r12], 0x41        ; REX.B
    mov byte [r12+1], 0x89      ; MOV r/m32, r32
    mov byte [r12+2], 0x04      ; ModRM: SIB mode
    mov byte [r12+3], 0x0E      ; SIB: base=r14, index=rcx
    add r12, 4

    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.SD: sd rs2', offset(rs1')
;------------------------------------------------------------------------------
.c_sd:
    mov edx, r13d
    shr edx, 2
    and edx, 0x7
    add edx, 8                  ; rs2

    mov ebx, r13d
    shr ebx, 7
    and ebx, 0x7
    add ebx, 8                  ; rs1

    ; offset[5:3] = inst[12:10], offset[7:6] = inst[6:5]
    xor eax, eax

    mov ecx, r13d
    shr ecx, 10
    and ecx, 0x7
    shl ecx, 3
    or eax, ecx

    mov ecx, r13d
    shr ecx, 5
    and ecx, 0x3
    shl ecx, 6
    or eax, ecx

    push rax
    push rdx

    ; Load rs1 into RCX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4

    pop rdx

    ; Load rs2 into RAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, edx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4

    pop rdx                     ; offset

    ; Add offset
    mov byte [r12], 0x48
    mov byte [r12+1], 0x81
    mov byte [r12+2], 0xC1
    mov [r12+3], edx
    add r12, 7

    ; Store to [r14+rcx]: mov [r14+rcx], rax
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0x89      ; MOV r/m64, r64
    mov byte [r12+2], 0x04      ; ModRM: SIB mode
    mov byte [r12+3], 0x0E      ; SIB: base=r14, index=rcx
    add r12, 4

    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.ADDI: addi rd, rd, imm (rd in bits 11:7, imm in bits 12|6:2)
;------------------------------------------------------------------------------
.c_addi:
    ; rd = bits 11:7
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x1F

    test ecx, ecx
    jz .c_emit_nop              ; C.NOP if rd == 0

    ; imm[5] = bit 12, imm[4:0] = bits 6:2
    mov eax, r13d
    shr eax, 2
    and eax, 0x1F               ; imm[4:0]

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 5
    or eax, edx                 ; imm[5:0]

    ; Sign-extend from bit 5
    test eax, 0x20
    jz .c_addi_positive
    or eax, 0xFFFFFFC0
.c_addi_positive:

    ; Load rd into RAX
    push rcx
    push rax
    mov ebx, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rax
    pop rcx

    ; Add immediate
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], eax
    add r12, 6

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.ADDIW: addiw rd, rd, imm (RV64 only)
;------------------------------------------------------------------------------
.c_addiw:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x1F

    test ecx, ecx
    jz .c_emit_nop

    ; imm same as C.ADDI
    mov eax, r13d
    shr eax, 2
    and eax, 0x1F

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 5
    or eax, edx

    test eax, 0x20
    jz .c_addiw_positive
    or eax, 0xFFFFFFC0
.c_addiw_positive:

    ; Load rd
    push rcx
    push rax
    mov ebx, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rax
    pop rcx

    ; Add immediate (32-bit)
    mov byte [r12], 0x05        ; add eax, imm32
    mov [r12+1], eax
    add r12, 5

    ; Sign-extend: movsxd rax, eax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.LI: addi rd, x0, imm
;------------------------------------------------------------------------------
.c_li:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x1F

    test ecx, ecx
    jz .c_emit_nop

    ; Extract immediate
    mov eax, r13d
    shr eax, 2
    and eax, 0x1F

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 5
    or eax, edx

    ; Sign-extend
    test eax, 0x20
    jz .c_li_positive
    or eax, 0xFFFFFFC0
.c_li_positive:

    ; mov rax, imm32 (sign-extended)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC0      ; mov rax, imm32
    mov [r12+3], eax
    add r12, 7

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.LUI / C.ADDI16SP
;------------------------------------------------------------------------------
.c_lui_addi16sp:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x1F

    cmp ecx, 2
    je .c_addi16sp

    test ecx, ecx
    jz .c_emit_nop              ; Reserved

    ; C.LUI: lui rd, nzimm
    ; imm[17] = bit 12, imm[16:12] = bits 6:2
    mov eax, r13d
    shr eax, 2
    and eax, 0x1F
    shl eax, 12                 ; imm[16:12]

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 17
    or eax, edx                 ; imm[17]

    ; Sign-extend from bit 17
    test eax, 0x20000
    jz .c_lui_no_sign
    or eax, 0xFFFC0000
.c_lui_no_sign:

    ; mov rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC0
    mov [r12+3], eax
    add r12, 7

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

.c_addi16sp:
    ; C.ADDI16SP: addi x2, x2, nzimm
    ; imm[9] = bit 12, imm[4|6|8:7|5] = bits 6:2
    xor eax, eax

    ; imm[5] = inst[2]
    mov edx, r13d
    shr edx, 2
    and edx, 0x1
    shl edx, 5
    or eax, edx

    ; imm[8:7] = inst[4:3]
    mov edx, r13d
    shr edx, 3
    and edx, 0x3
    shl edx, 7
    or eax, edx

    ; imm[6] = inst[5]
    mov edx, r13d
    shr edx, 5
    and edx, 0x1
    shl edx, 6
    or eax, edx

    ; imm[4] = inst[6]
    mov edx, r13d
    shr edx, 6
    and edx, 0x1
    shl edx, 4
    or eax, edx

    ; imm[9] = inst[12]
    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 9
    or eax, edx

    ; Sign-extend from bit 9
    test eax, 0x200
    jz .c_addi16sp_no_sign
    or eax, 0xFFFFFC00
.c_addi16sp_no_sign:

    ; Load sp (x2)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov byte [r12+3], 16        ; x2 * 8
    add r12, 4

    ; Add immediate
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], eax
    add r12, 6

    ; Store to x2
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x43
    mov byte [r12+3], 16
    add r12, 4

    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.ALU operations (funct3 = 100)
;------------------------------------------------------------------------------
.c_alu:
    ; bits 11:10 determine sub-operation
    mov eax, r13d
    shr eax, 10
    and eax, 0x3

    cmp eax, 0
    je .c_srli

    cmp eax, 1
    je .c_srai

    cmp eax, 2
    je .c_andi

    ; eax == 3: register-register ops
    ; bits 6:5 further distinguish
    mov eax, r13d
    shr eax, 5
    and eax, 0x3

    ; bit 12 distinguishes W-variants
    mov edx, r13d
    shr edx, 12
    and edx, 0x1

    test edx, edx
    jnz .c_alu_w_variants

    cmp eax, 0
    je .c_sub

    cmp eax, 1
    je .c_xor

    cmp eax, 2
    je .c_or

    cmp eax, 3
    je .c_and

    jmp .c_emit_nop

.c_alu_w_variants:
    cmp eax, 0
    je .c_subw

    cmp eax, 1
    je .c_addw

    jmp .c_emit_nop

;------------------------------------------------------------------------------
; C.SRLI: srli rd', rd', shamt
;------------------------------------------------------------------------------
.c_srli:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8                  ; rd

    ; shamt[5] = bit 12, shamt[4:0] = bits 6:2
    mov eax, r13d
    shr eax, 2
    and eax, 0x1F

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 5
    or eax, edx

    ; Load rd
    push rcx
    push rax
    mov ebx, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rax
    pop rcx

    ; shr rax, imm8
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC1
    mov byte [r12+2], 0xE8      ; shr rax, imm8
    mov byte [r12+3], al
    add r12, 4

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.SRAI: srai rd', rd', shamt
;------------------------------------------------------------------------------
.c_srai:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8

    mov eax, r13d
    shr eax, 2
    and eax, 0x1F

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 5
    or eax, edx

    push rcx
    push rax
    mov ebx, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rax
    pop rcx

    ; sar rax, imm8
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC1
    mov byte [r12+2], 0xF8
    mov byte [r12+3], al
    add r12, 4

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.ANDI: andi rd', rd', imm
;------------------------------------------------------------------------------
.c_andi:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8

    mov eax, r13d
    shr eax, 2
    and eax, 0x1F

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 5
    or eax, edx

    ; Sign-extend
    test eax, 0x20
    jz .c_andi_positive
    or eax, 0xFFFFFFC0
.c_andi_positive:

    push rcx
    push rax
    mov ebx, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rax
    pop rcx

    ; and rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x25
    mov [r12+2], eax
    add r12, 6

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.SUB: sub rd', rd', rs2'
;------------------------------------------------------------------------------
.c_sub:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8                  ; rd/rs1

    mov edx, r13d
    shr edx, 2
    and edx, 0x7
    add edx, 8                  ; rs2

    ; Load rd/rs1
    push rcx
    push rdx
    mov ebx, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rdx
    pop rcx

    ; Load rs2 to temp
    push rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x53      ; mov rdx, [rbx + disp8]
    mov eax, edx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rcx

    ; sub rax, rdx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x29
    mov byte [r12+2], 0xD0
    add r12, 3

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.XOR: xor rd', rd', rs2'
;------------------------------------------------------------------------------
.c_xor:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8

    mov edx, r13d
    shr edx, 2
    and edx, 0x7
    add edx, 8

    push rcx
    push rdx
    mov ebx, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rdx
    pop rcx

    push rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x53
    mov eax, edx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rcx

    ; xor rax, rdx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x31
    mov byte [r12+2], 0xD0
    add r12, 3

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.OR: or rd', rd', rs2'
;------------------------------------------------------------------------------
.c_or:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8

    mov edx, r13d
    shr edx, 2
    and edx, 0x7
    add edx, 8

    push rcx
    push rdx
    mov ebx, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rdx
    pop rcx

    push rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x53
    mov eax, edx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rcx

    ; or rax, rdx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x09
    mov byte [r12+2], 0xD0
    add r12, 3

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.AND: and rd', rd', rs2'
;------------------------------------------------------------------------------
.c_and:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8

    mov edx, r13d
    shr edx, 2
    and edx, 0x7
    add edx, 8

    push rcx
    push rdx
    mov ebx, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rdx
    pop rcx

    push rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x53
    mov eax, edx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rcx

    ; and rax, rdx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x21
    mov byte [r12+2], 0xD0
    add r12, 3

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.SUBW: subw rd', rd', rs2' (RV64)
;------------------------------------------------------------------------------
.c_subw:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8

    mov edx, r13d
    shr edx, 2
    and edx, 0x7
    add edx, 8

    push rcx
    push rdx
    mov ebx, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rdx
    pop rcx

    push rcx
    mov byte [r12], 0x8B        ; mov edx, [rbx + disp8] (32-bit)
    mov byte [r12+1], 0x53
    mov eax, edx
    shl eax, 3
    mov byte [r12+2], al
    add r12, 3
    pop rcx

    ; sub eax, edx
    mov byte [r12], 0x29
    mov byte [r12+1], 0xD0
    add r12, 2

    ; Sign-extend
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.ADDW: addw rd', rd', rs2' (RV64)
;------------------------------------------------------------------------------
.c_addw:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8

    mov edx, r13d
    shr edx, 2
    and edx, 0x7
    add edx, 8

    push rcx
    push rdx
    mov ebx, ecx
    mov byte [r12], 0x8B        ; mov eax, [rbx + disp8]
    mov byte [r12+1], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+2], al
    add r12, 3
    pop rdx
    pop rcx

    push rcx
    mov byte [r12], 0x8B
    mov byte [r12+1], 0x53
    mov eax, edx
    shl eax, 3
    mov byte [r12+2], al
    add r12, 3
    pop rcx

    ; add eax, edx
    mov byte [r12], 0x01
    mov byte [r12+1], 0xD0
    add r12, 2

    ; Sign-extend
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.J: jal x0, offset (unconditional jump, no link)
;------------------------------------------------------------------------------
.c_j_impl:
    ; For block translation, this is handled specially
    ; Just emit NOP here - the block handler computes the target
    jmp .c_emit_nop

;------------------------------------------------------------------------------
; C.BEQZ / C.BNEZ
;------------------------------------------------------------------------------
.c_beqz:
.c_bnez:
    ; These are handled by the block-ending code
    ; Just emit the comparison and conditional code here
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8                  ; rs1

    ; Load rs1
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ecx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4

    ; test rax, rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x85
    mov byte [r12+2], 0xC0
    add r12, 3

    ; Check if BEQZ or BNEZ
    mov eax, r13d
    shr eax, 13
    and eax, 0x7

    cmp eax, 6
    jne .c_is_bnez

    ; BEQZ: jne .not_taken (skip if NZ)
    mov byte [r12], 0x0F
    mov byte [r12+1], 0x85      ; JNE rel32
    mov dword [r12+2], 0        ; Placeholder - will be fixed by linking
    add r12, 6
    jmp .c_calc_size

.c_is_bnez:
    ; BNEZ: je .not_taken (skip if Z)
    mov byte [r12], 0x0F
    mov byte [r12+1], 0x84      ; JE rel32
    mov dword [r12+2], 0
    add r12, 6
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.SLLI: slli rd, rd, shamt
;------------------------------------------------------------------------------
.c_slli:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x1F               ; rd (full 5 bits)

    test ecx, ecx
    jz .c_emit_nop

    ; shamt[5] = bit 12, shamt[4:0] = bits 6:2
    mov eax, r13d
    shr eax, 2
    and eax, 0x1F

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 5
    or eax, edx

    push rcx
    push rax
    mov ebx, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rax
    pop rcx

    ; shl rax, imm8
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC1
    mov byte [r12+2], 0xE0
    mov byte [r12+3], al
    add r12, 4

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.LWSP: lw rd, offset(sp)
;------------------------------------------------------------------------------
.c_lwsp:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x1F

    test ecx, ecx
    jz .c_emit_nop              ; Reserved

    ; offset[5] = bit 12, offset[4:2] = bits 6:4, offset[7:6] = bits 3:2
    xor eax, eax

    mov edx, r13d
    shr edx, 4
    and edx, 0x7
    shl edx, 2
    or eax, edx

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 5
    or eax, edx

    mov edx, r13d
    shr edx, 2
    and edx, 0x3
    shl edx, 6
    or eax, edx

    ; Load sp
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov byte [r12+3], 16
    add r12, 4

    ; Add offset
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], eax
    add r12, 6

    ; Load 32-bit sign-extended from [r14+rax]
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0x63      ; MOVSXD
    mov byte [r12+2], 0x04      ; ModRM: SIB mode
    mov byte [r12+3], 0x06      ; SIB: base=r14, index=rax
    add r12, 4

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.LDSP: ld rd, offset(sp)
;------------------------------------------------------------------------------
.c_ldsp:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x1F

    test ecx, ecx
    jz .c_emit_nop

    ; offset[5] = bit 12, offset[4:3] = bits 6:5, offset[8:6] = bits 4:2
    xor eax, eax

    mov edx, r13d
    shr edx, 5
    and edx, 0x3
    shl edx, 3
    or eax, edx

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 5
    or eax, edx

    mov edx, r13d
    shr edx, 2
    and edx, 0x7
    shl edx, 6
    or eax, edx

    ; Load sp
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov byte [r12+3], 16
    add r12, 4

    ; Add offset
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], eax
    add r12, 6

    ; Load 64-bit from [r14+rax] (r14 = guest memory base)
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0x8B      ; MOV
    mov byte [r12+2], 0x04      ; ModRM: SIB mode
    mov byte [r12+3], 0x06      ; SIB: base=r14, index=rax
    add r12, 4

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.CR format: C.JR, C.MV, C.EBREAK, C.JALR, C.ADD
;------------------------------------------------------------------------------
.c_cr_format:
    ; bit 12 and rs2 determine instruction
    mov eax, r13d
    shr eax, 12
    and eax, 0x1                ; bit 12

    mov edx, r13d
    shr edx, 2
    and edx, 0x1F               ; rs2

    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x1F               ; rd/rs1

    test eax, eax               ; Test bit 12
    jnz .c_cr_bit12_set

    ; bit 12 = 0: C.JR or C.MV
    test edx, edx
    jz .c_jr                    ; rs2 == 0: C.JR
    jmp .c_mv                   ; rs2 != 0: C.MV

.c_cr_bit12_set:
    ; bit 12 = 1: C.EBREAK, C.JALR, or C.ADD
    test ecx, ecx
    jz .c_ebreak                ; rs1 == 0: C.EBREAK

    test edx, edx
    jz .c_jalr                  ; rs2 == 0: C.JALR
    jmp .c_add                  ; C.ADD

.c_jr:
    ; C.JR: jalr x0, rs1, 0
    test ecx, ecx
    jz .c_emit_nop              ; Reserved

    ; Load rs1 into RAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ecx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4

    ; Store to PC (indirect jump target)
    ; mov [r15], rax
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x07
    add r12, 3

    jmp .c_calc_size

.c_mv:
    ; C.MV: add rd, x0, rs2
    ; Load rs2
    push rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, edx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rcx

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

.c_ebreak:
    ; C.EBREAK - emit INT3
    mov byte [r12], 0xCC
    add r12, 1
    jmp .c_calc_size

.c_jalr:
    ; C.JALR: jalr x1, rs1, 0
    ; Save return address (PC + 2) to ra (x1)
    ; Then jump to rs1

    ; Load rs1 into RAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ecx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4

    ; Store to PC
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x07
    add r12, 3

    ; Note: Return address should be stored - but we handle this at block level
    jmp .c_calc_size

.c_add:
    ; C.ADD: add rd, rd, rs2
    push rcx
    push rdx

    ; Load rd
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ecx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4

    pop rdx
    pop rcx

    ; Load rs2 to temp
    push rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x53
    mov eax, edx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rcx

    ; add rax, rdx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xD0
    add r12, 3

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.SWSP: sw rs2, offset(sp)
;------------------------------------------------------------------------------
.c_swsp:
    mov edx, r13d
    shr edx, 2
    and edx, 0x1F               ; rs2

    ; offset[5:2] = bits 12:9, offset[7:6] = bits 8:7
    xor eax, eax

    mov ecx, r13d
    shr ecx, 9
    and ecx, 0xF
    shl ecx, 2
    or eax, ecx

    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x3
    shl ecx, 6
    or eax, ecx

    push rax
    push rdx

    ; Load sp into RCX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov byte [r12+3], 16
    add r12, 4

    pop rdx

    ; Load rs2 into EAX
    mov byte [r12], 0x8B
    mov byte [r12+1], 0x43
    mov ecx, edx
    shl ecx, 3
    mov byte [r12+2], cl
    add r12, 3

    pop rdx                     ; offset

    ; Add offset
    mov byte [r12], 0x48
    mov byte [r12+1], 0x81
    mov byte [r12+2], 0xC1
    mov [r12+3], edx
    add r12, 7

    ; Store to [r14+rcx]: mov [r14+rcx], eax
    mov byte [r12], 0x41        ; REX.B
    mov byte [r12+1], 0x89      ; MOV r/m32, r32
    mov byte [r12+2], 0x04      ; ModRM: SIB mode
    mov byte [r12+3], 0x0E      ; SIB: base=r14, index=rcx
    add r12, 4

    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.SDSP: sd rs2, offset(sp)
;------------------------------------------------------------------------------
.c_sdsp:
    mov edx, r13d
    shr edx, 2
    and edx, 0x1F

    ; offset[5:3] = bits 12:10, offset[8:6] = bits 9:7
    xor eax, eax

    mov ecx, r13d
    shr ecx, 10
    and ecx, 0x7
    shl ecx, 3
    or eax, ecx

    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    shl ecx, 6
    or eax, ecx

    push rax
    push rdx

    ; Load sp into RCX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov byte [r12+3], 16
    add r12, 4

    pop rdx

    ; Load rs2 into RAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov ecx, edx
    shl ecx, 3
    mov byte [r12+3], cl
    add r12, 4

    pop rdx

    ; Add offset
    mov byte [r12], 0x48
    mov byte [r12+1], 0x81
    mov byte [r12+2], 0xC1
    mov [r12+3], edx
    add r12, 7

    ; Store to [r14+rcx]: mov [r14+rcx], rax
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0x89      ; MOV r/m64, r64
    mov byte [r12+2], 0x04      ; ModRM: SIB mode
    mov byte [r12+3], 0x0E      ; SIB: base=r14, index=rcx
    add r12, 4

    jmp .c_calc_size

;------------------------------------------------------------------------------
; Helper: emit NOP
;------------------------------------------------------------------------------
.c_emit_nop:
    mov byte [r12], 0x90
    add r12, 1
    jmp .c_calc_size

;------------------------------------------------------------------------------
; Helper: store RAX to rd (ECX = rd)
;------------------------------------------------------------------------------
.c_emit_store_rd:
    test ecx, ecx
    jz .c_store_rd_skip         ; Don't store to x0

    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x43
    mov eax, ecx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4

.c_store_rd_skip:
    ret

;------------------------------------------------------------------------------
; Calculate size and return
;------------------------------------------------------------------------------
.c_calc_size:
    mov rax, r12
    sub rax, r14

.c_done:
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
    ; Load [RBX + rs1*8] into RAX
    ; EBX = rs1
    mov eax, ebx
    shl eax, 3              ; eax = rs1 * 8

    ; Check if displacement fits in 8 bits (signed: -128 to 127)
    cmp eax, 127
    jg .load_disp32

    ; 8-bit displacement: mov rax, [rbx + disp8]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43      ; ModRM: [rbx + disp8]
    mov [r12+3], al
    add r12, 4
    ret

.load_disp32:
    ; 32-bit displacement: mov rax, [rbx + disp32]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x83      ; ModRM: [rbx + disp32]
    mov [r12+3], eax
    add r12, 7
    ret

;==============================================================================
; emit_store_rd - Store RAX to rd
; Expects: ECX = rd
;==============================================================================
emit_store_rd:
    ; Store RAX to [RBX + rd*8]
    ; ECX = rd
    mov r15d, ecx
    mov eax, ecx
    shl eax, 3              ; eax = rd * 8

    ; Check if displacement fits in 8 bits (signed: -128 to 127)
    cmp eax, 127
    jg .store_disp32

    ; 8-bit displacement: mov [rbx + disp8], rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x43      ; ModRM: [rbx + disp8]
    mov [r12+3], al
    add r12, 4
    ret

.store_disp32:
    ; 32-bit displacement: mov [rbx + disp32], rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x83      ; ModRM: [rbx + disp32]
    mov [r12+3], eax
    add r12, 7
    ret

;==============================================================================
; emit_load_reg_to_rax - Load RISC-V register to RAX
; Input: ECX = register number
;==============================================================================
emit_load_reg_to_rax:
    test ecx, ecx
    jz .load_zero_rax

    mov eax, ecx
    shl eax, 3              ; offset = reg * 8

    cmp eax, 127
    jg .load_rax_disp32

    ; mov rax, [rbx + disp8]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov [r12+3], al
    add r12, 4
    ret

.load_rax_disp32:
    ; mov rax, [rbx + disp32]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x83
    mov [r12+3], eax
    add r12, 7
    ret

.load_zero_rax:
    ; xor rax, rax (x0 is always 0)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x31
    mov byte [r12+2], 0xC0
    add r12, 3
    ret

;==============================================================================
; emit_load_reg_to_rcx - Load RISC-V register to RCX
; Input: ECX = register number
;==============================================================================
emit_load_reg_to_rcx:
    test ecx, ecx
    jz .load_zero_rcx

    mov eax, ecx
    shl eax, 3              ; offset = reg * 8

    cmp eax, 127
    jg .load_rcx_disp32

    ; mov rcx, [rbx + disp8]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov [r12+3], al
    add r12, 4
    ret

.load_rcx_disp32:
    ; mov rcx, [rbx + disp32]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x8B
    mov [r12+3], eax
    add r12, 7
    ret

.load_zero_rcx:
    ; xor rcx, rcx (x0 is always 0)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x31
    mov byte [r12+2], 0xC9
    add r12, 3
    ret

;==============================================================================
; emit_store_rax_to_rd - Store RAX to rd (same as emit_store_rd)
; Input: ECX = rd
;==============================================================================
emit_store_rax_to_rd:
    jmp emit_store_rd

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
    sub rsp, 40                     ; Shadow space for Windows calls

    ; Zero out the block cache (mark all entries invalid)
    lea rdi, [block_cache]
    mov rcx, BLOCK_CACHE_SIZE * BLOCK_ENTRY_SIZE / 8
    xor eax, eax
    rep stosq

    ; Initialise code buffer pointer to start of buffer
    lea rax, [code_buffer]
    mov [code_buf_ptr], rax

    ; Get stdout handle for console output
    mov ecx, -11                    ; STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [stdout_handle], rax

    add rsp, 40
    pop rdi
    pop rcx
    pop rbx
    ret

;==============================================================================
; link_trampoline
; Blocks jump here initially - just returns to the dispatch loop
; When blocks are linked, the jump is patched to skip this
; "A trampoline, but for code. Boing!"
;==============================================================================
link_trampoline:
    ret

;==============================================================================
; link_block
; Patch a block's exit to jump directly to another block
; Input:  RDI = pointer to source block entry
;         RSI = pointer to target block entry
; Output: RAX = 1 if linked successfully, 0 if failed
; "Making friends between blocks since 2024"
;==============================================================================
link_block:
    push rbx

    ; Get the address of the jmp instruction to patch
    mov rax, [rdi + BLOCK_LINK_ADDR]
    test rax, rax
    jz .link_fail                   ; No link address stored

    ; Get target code address
    mov rbx, [rsi + BLOCK_CODE_PTR]
    test rbx, rbx
    jz .link_fail                   ; No target code

    ; Calculate relative offset for jmp
    ; offset = target - (jmp_addr + 5)
    ; jmp rel32 is: E9 xx xx xx xx (5 bytes)
    lea rcx, [rax + 5]              ; Address after the jmp instruction
    sub rbx, rcx                    ; offset = target - (jmp + 5)

    ; Patch the jmp offset (it's at jmp_addr + 1)
    mov [rax + 1], ebx

    mov eax, 1
    pop rbx
    ret

.link_fail:
    xor eax, eax
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

    ; Check if this is a compressed instruction (bits[1:0] != 11)
    mov ecx, eax
    and ecx, 0x3
    cmp ecx, 0x3
    jne .is_compressed

    ; --- 32-bit instruction path ---
    mov ecx, eax
    and ecx, 0x7F                   ; Extract opcode

    cmp ecx, RV_OP_JAL
    je .is_jal

    cmp ecx, RV_OP_JALR
    je .is_jalr

    cmp ecx, RV_OP_BRANCH
    je .is_branch

    cmp ecx, RV_OP_SYSTEM
    je .check_ecall

    ; Not a block-ender - translate normally
    mov edi, eax                    ; instruction
    mov rsi, r12                    ; output buffer
    call translate_instruction
    add r12, rax                    ; Advance output pointer

    ; Advance PC by 4
    add r13, 4
    jmp .translate_loop

    ; --- 16-bit compressed instruction path ---
.is_compressed:
    ; Get just the 16-bit instruction
    movzx eax, word [r14 + r13]
    mov [rbp-24], eax               ; Save 16-bit instruction

    ; Check for compressed block-enders:
    ; Q1 (01): C.J (funct3=101), C.BEQZ (funct3=110), C.BNEZ (funct3=111)
    ; Q2 (10): C.JR/C.JALR (funct3=100, bit12 varies)

    mov ecx, eax
    and ecx, 0x3                    ; Quadrant

    cmp ecx, 0x1                    ; Quadrant 1?
    je .check_q1_block_ender

    cmp ecx, 0x2                    ; Quadrant 2?
    je .check_q2_block_ender

    ; Quadrant 0 has no block-enders, translate normally
    jmp .translate_compressed_normal

.check_q1_block_ender:
    ; Check funct3 (bits 15:13)
    mov ecx, eax
    shr ecx, 13
    and ecx, 0x7

    cmp ecx, 5                      ; C.J (funct3=101)
    je .is_c_j

    cmp ecx, 6                      ; C.BEQZ (funct3=110)
    je .is_c_branch

    cmp ecx, 7                      ; C.BNEZ (funct3=111)
    je .is_c_branch

    jmp .translate_compressed_normal

.check_q2_block_ender:
    ; Check funct3 (bits 15:13)
    mov ecx, eax
    shr ecx, 13
    and ecx, 0x7

    cmp ecx, 4                      ; C.JR/C.MV/C.JALR/C.ADD (funct3=100)
    jne .translate_compressed_normal

    ; Distinguish by bit 12 and rs2
    ; If rs2 == 0 (bits 6:2 == 0): C.JR (bit12=0) or C.JALR (bit12=1)
    ; If rs2 != 0: C.MV (bit12=0) or C.ADD (bit12=1)
    mov ecx, eax
    shr ecx, 2
    and ecx, 0x1F                   ; rs2 field
    test ecx, ecx
    jnz .translate_compressed_normal  ; C.MV or C.ADD - not block-enders

    ; rs2 == 0, so this is C.JR or C.JALR - block-enders
    jmp .is_c_jr_jalr

.translate_compressed_normal:
    ; Translate compressed instruction
    movzx edi, word [rbp-24]        ; 16-bit instruction
    mov rsi, r12                    ; output buffer
    call translate_compressed
    add r12, rax                    ; Advance output pointer

    ; Advance PC by 2 (compressed)
    add r13, 2
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

.check_ecall:
    ; Check if this is actually ECALL (funct3=0, imm=0)
    ; or EBREAK (funct3=0, imm=1)
    ; CSR instructions (funct3 != 0) are NOT block-enders
    mov eax, [rbp-24]
    shr eax, 12
    and eax, 0x7                    ; funct3
    test eax, eax               ; Test funct3
    jnz .not_block_ender            ; CSR instructions (funct3 != 0) - not block-enders

    ; It's ECALL or EBREAK - these ARE block-enders
    jmp .is_ecall

.not_block_ender:
    ; This is a CSR instruction, translate normally
    mov edi, [rbp-24]
    mov rsi, r12
    call translate_instruction
    add r12, rax
    add r13, 4
    jmp .translate_loop

.is_ecall:
    ; ECALL/EBREAK - block-ending instruction
    ; First, emit code to store current PC to rv_pc
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0xC7      ; MOV r/m64, imm32
    mov byte [r12+2], 0x07      ; ModRM: [r15]
    mov [r12+3], r13d           ; Current PC (32-bit immediate)
    add r12, 7

    ; Translate the ECALL/EBREAK
    mov edi, [rbp-24]
    mov rsi, r12
    call translate_instruction
    add r12, rax

    ; Next PC = current PC + 4
    lea rax, [r13 + 4]
    mov [r15 + BLOCK_NEXT_PC], rax

    mov dword [r15 + BLOCK_EXIT_TYPE], EXIT_ECALL
    jmp .finish_block

;------------------------------------------------------------------------------
; Compressed block-enders
;------------------------------------------------------------------------------
.is_c_j:
    ; C.J - unconditional jump (expands to jal x0, offset)
    ; Unlike JAL, C.J doesn't write a return address (rd=x0)
    ; We need to compute target and emit code to update PC

    ; Extract C.J target from CB format
    ; According to RISC-V spec:
    ; inst[12] = imm[11], inst[11] = imm[4], inst[10:9] = imm[9:8]
    ; inst[8] = imm[10], inst[7] = imm[6], inst[6] = imm[7]
    ; inst[5:3] = imm[3:1], inst[2] = imm[5]
    movzx eax, word [rbp-24]
    xor ecx, ecx                    ; Build immediate in ECX

    ; imm[11] = inst[12]
    mov edx, eax
    shr edx, 12
    and edx, 1
    shl edx, 11
    or ecx, edx

    ; imm[4] = inst[11]
    mov edx, eax
    shr edx, 11
    and edx, 1
    shl edx, 4
    or ecx, edx

    ; imm[9:8] = inst[10:9]
    mov edx, eax
    shr edx, 9
    and edx, 3
    shl edx, 8
    or ecx, edx

    ; imm[10] = inst[8]
    mov edx, eax
    shr edx, 8
    and edx, 1
    shl edx, 10
    or ecx, edx

    ; imm[6] = inst[7]
    mov edx, eax
    shr edx, 7
    and edx, 1
    shl edx, 6
    or ecx, edx

    ; imm[7] = inst[6]
    mov edx, eax
    shr edx, 6
    and edx, 1
    shl edx, 7
    or ecx, edx

    ; imm[3:1] = inst[5:3]
    mov edx, eax
    shr edx, 3
    and edx, 7
    shl edx, 1
    or ecx, edx

    ; imm[5] = inst[2]
    mov edx, eax
    shr edx, 2
    and edx, 1
    shl edx, 5
    or ecx, edx

    ; Sign-extend from bit 11
    test ecx, 0x800
    jz .c_j_no_sign
    or ecx, 0xFFFFF000
.c_j_no_sign:

    ; Target = PC + imm
    movsxd rax, ecx
    add rax, r13                    ; RAX = target PC

    ; Store target in block metadata
    mov [r15 + BLOCK_NEXT_PC], rax
    mov dword [r15 + BLOCK_EXIT_TYPE], EXIT_JUMP

    ; Now emit x86 code to write target PC to [r15]
    ; Emit: mov qword [r15], target_pc (immediate)
    mov byte [r12], 0x49            ; REX.WB
    mov byte [r12+1], 0xC7          ; MOV r/m64, imm32
    mov byte [r12+2], 0x07          ; ModRM: [r15]
    mov [r12+3], eax                ; Target PC (32-bit, sign-extended)
    add r12, 7

    jmp .finish_block

.is_c_branch:
    ; C.BEQZ/C.BNEZ - conditional branch
    ; Must emit code that properly updates PC based on branch outcome

    ; First, emit code to store current PC to [r15]
    mov byte [r12], 0x49
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0x07
    mov [r12+3], r13d
    add r12, 7

    ; Extract branch offset from CB format first (need it for code generation)
    ; imm[8|4:3] = inst[12|11:10], imm[7:6|2:1|5] = inst[6:5|4:3|2]
    movzx eax, word [rbp-24]
    xor ecx, ecx

    ; imm[8] = inst[12] (sign bit)
    mov edx, eax
    shr edx, 12
    and edx, 1
    shl edx, 8
    or ecx, edx

    ; imm[4:3] = inst[11:10]
    mov edx, eax
    shr edx, 10
    and edx, 3
    shl edx, 3
    or ecx, edx

    ; imm[7:6] = inst[6:5]
    mov edx, eax
    shr edx, 5
    and edx, 3
    shl edx, 6
    or ecx, edx

    ; imm[2:1] = inst[4:3]
    mov edx, eax
    shr edx, 3
    and edx, 3
    shl edx, 1
    or ecx, edx

    ; imm[5] = inst[2]
    mov edx, eax
    shr edx, 2
    and edx, 1
    shl edx, 5
    or ecx, edx

    ; Sign-extend from bit 8
    test ecx, 0x100
    jz .c_branch_no_sign
    or ecx, 0xFFFFFE00
.c_branch_no_sign:
    push rcx                    ; Save branch offset

    ; Store metadata for block cache
    movsxd rax, ecx
    add rax, r13
    mov [r15 + BLOCK_TAKEN_PC], rax
    lea rax, [r13 + 2]
    mov [r15 + BLOCK_NOT_TAKEN_PC], rax

    ; Now emit the actual branch code
    ; Get rs1' (in bits 9:7, add 8 for x8-x15)
    movzx eax, word [rbp-24]
    shr eax, 7
    and eax, 0x7
    add eax, 8                  ; rs1 = x8 + rs1'

    ; Emit: mov rax, [rbx + rs1*8]  (load rs1)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4

    ; Emit: test rax, rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x85
    mov byte [r12+2], 0xC0
    add r12, 3

    ; Check if BEQZ or BNEZ to emit correct conditional jump
    movzx eax, word [rbp-24]
    shr eax, 13
    and eax, 0x7
    cmp eax, 6
    jne .c_branch_is_bnez

    ; BEQZ: je taken (branch if zero)
    mov byte [r12], 0x74        ; JE rel8
    jmp .c_branch_emit_common

.c_branch_is_bnez:
    ; BNEZ: jne taken (branch if not zero)
    mov byte [r12], 0x75        ; JNE rel8

.c_branch_emit_common:
    ; Jcc +10 (skip not-taken path: mov rdx,2 is 7 bytes + jmp +8 is 2 bytes + nop is 1 byte = 10)
    mov byte [r12+1], 10
    add r12, 2

    ; Not taken: mov rdx, 2 (compressed instruction size)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC2
    mov dword [r12+3], 2
    add r12, 7

    ; jmp +8 (skip taken path - nop is 1 byte + mov rdx,imm is 7 bytes = 8)
    mov byte [r12], 0xEB
    mov byte [r12+1], 8
    add r12, 2

    ; nop for alignment
    mov byte [r12], 0x90
    add r12, 1

    ; Taken: mov rdx, imm
    pop rcx                     ; Restore branch offset
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC2
    mov [r12+3], ecx            ; branch offset
    add r12, 7

    ; Common: update PC = [r15] + rdx
    ; Emit: mov rax, [r15]
    mov byte [r12], 0x49
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x07
    add r12, 3

    ; Emit: add rax, rdx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xD0
    add r12, 3

    ; Emit: mov [r15], rax
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x07
    add r12, 3

    mov dword [r15 + BLOCK_EXIT_TYPE], EXIT_BRANCH
    jmp .finish_block

.is_c_jr_jalr:
    ; C.JR/C.JALR - indirect jump
    ; Emit code to store current PC
    mov byte [r12], 0x49
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0x07
    mov [r12+3], r13d
    add r12, 7

    ; Translate the C.JR/C.JALR
    movzx edi, word [rbp-24]
    mov rsi, r12
    call translate_compressed
    add r12, rax

    mov dword [r15 + BLOCK_EXIT_TYPE], EXIT_INDIRECT
    mov qword [r15 + BLOCK_NEXT_PC], 0
    jmp .finish_block

.end_block_fallthrough:
    ; Hit instruction limit - fall through to next instruction
    mov [r15 + BLOCK_NEXT_PC], r13
    mov dword [r15 + BLOCK_EXIT_TYPE], EXIT_JUMP

.finish_block:
    ; Emit block epilogue: JMP to link_trampoline (can be patched for linking)
    ; Store the jmp address so we can patch it later
    mov [r15 + BLOCK_LINK_ADDR], r12

    ; Emit: jmp rel32 (E9 xx xx xx xx)
    mov byte [r12], 0xE9

    ; Calculate offset: link_trampoline - (jmp_addr + 5)
    lea rax, [r12 + 5]              ; Address after jmp instruction
    lea rcx, [link_trampoline]
    sub rcx, rax                    ; offset = trampoline - (jmp + 5)
    mov [r12 + 1], ecx
    add r12, 5

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
    ; Update debug counters
    mov [debug_block_count], r12
    mov rcx, [rbp-32]
    mov rax, [rcx]
    mov [debug_last_pc], rax

    ; Check block limit
    mov rax, [rbp-40]
    test rax, rax
    jz .no_limit
    cmp r12, rax
    jge .done
.no_limit:
    inc r12

    ; Clear ecall_pending flag before execution
    mov byte [ecall_pending], 0

    ; Get current PC
    mov rcx, [rbp-32]
    mov rdi, [rcx]              ; RDI = current PC

    ; Check for NULL PC (bad return address)
    test rdi, rdi
    jz .null_pc_error

    ; Translate/lookup block
    mov rsi, [rbp-16]           ; guest memory
    call translate_block
    test rax, rax
    jz .xlate_failed            ; No block = stop

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
    ; Check ecall_pending flag (set by ECALL blocks at runtime)
    cmp byte [ecall_pending], 0
    jne .handle_ecall

    ; Not an ECALL - try to link this block for future speedup
    ; Only link blocks with EXIT_JUMP (direct unconditional jump)
    mov rax, [rbp-48]
    mov ecx, [rax + BLOCK_EXIT_TYPE]
    cmp ecx, EXIT_JUMP
    jne .exec_loop              ; Indirect/branch - don't link

    ; Look up target block by current PC
    mov rcx, [rbp-32]
    mov rdi, [rcx]
    call lookup_block
    test rax, rax
    jz .exec_loop               ; Target not cached yet - can't link

    ; Link source block to target block
    mov rdi, [rbp-48]           ; Source block
    mov rsi, rax                ; Target block
    call link_block

    jmp .exec_loop

.handle_ecall:
    ; ECALL - Linux RISC-V syscall ABI
    ; a7 (x17) = syscall number
    ; a0-a5 (x10-x15) = arguments
    ; a0 (x10) = return value (negative = -errno on error)
    mov rbx, [rbp-24]           ; rv_regs

    ; Get syscall number from a7 (x17)
    mov rax, [rbx + 17*8]

    ; Dispatch syscalls
    cmp rax, 29
    je .syscall_ioctl
    cmp rax, 56
    je .syscall_openat
    cmp rax, 57
    je .syscall_close
    cmp rax, 62
    je .syscall_lseek
    cmp rax, 63
    je .syscall_read
    cmp rax, 64
    je .syscall_write
    cmp rax, 80
    je .syscall_fstat
    cmp rax, 93
    je .syscall_exit
    cmp rax, 94
    je .syscall_exit            ; exit_group = exit for us
    cmp rax, 214
    je .syscall_brk
    cmp rax, 222
    je .syscall_mmap

    ; Conway/Doom-specific syscalls
    ; Common glibc startup syscalls
    cmp rax, 96                     ; set_tid_address
    je .syscall_set_tid_address
    cmp rax, 99                     ; set_robust_list
    je .syscall_stub_success
    cmp rax, 135                    ; rt_sigprocmask
    je .syscall_stub_success
    cmp rax, 160                    ; uname
    je .syscall_uname
    cmp rax, 172                    ; getpid
    je .syscall_getpid
    cmp rax, 174                    ; getuid
    je .syscall_getuid
    cmp rax, 175                    ; geteuid
    je .syscall_getuid
    cmp rax, 176                    ; getgid
    je .syscall_getuid
    cmp rax, 177                    ; getegid
    je .syscall_getuid
    cmp rax, 178                    ; gettid
    je .syscall_getpid
    cmp rax, 261                    ; prlimit64
    je .syscall_prlimit64
    cmp rax, 278                    ; getrandom
    je .syscall_getrandom
    cmp rax, 98                     ; futex
    je .syscall_futex
    cmp rax, 48                     ; faccessat
    je .syscall_faccessat
    cmp rax, 17                     ; getcwd
    je .syscall_getcwd
    cmp rax, 78                     ; readlinkat
    je .syscall_stub_error          ; Return -ENOENT
    cmp rax, 79                     ; fstatat
    je .syscall_fstatat
    cmp rax, 66                     ; writev
    je .syscall_writev

    cmp rax, 1000
    je .syscall_drawframe
    cmp rax, 1001
    je .syscall_sleepms

    ; Unknown syscall - return -ENOSYS (38)
    mov qword [rbx + 10*8], -38
    jmp .exec_loop

;------------------------------------------------------------------------------
; exit(status) / exit_group(status) - syscall 93/94
; a0 = exit code
;------------------------------------------------------------------------------
.syscall_exit:
    sub rsp, 40
    mov ecx, [rbx + 10*8]       ; a0 = exit code
    call ExitProcess

;------------------------------------------------------------------------------
; read(fd, buf, count) - syscall 63
; a0 = fd, a1 = buf (guest addr), a2 = count
; Returns bytes read, or negative errno
;------------------------------------------------------------------------------
.syscall_read:
    mov rax, [rbx + 10*8]           ; a0 = fd

    ; stdin - return EOF for now
    test rax, rax
    jz .read_eof

    ; Check if it's a file fd
    cmp rax, FD_OFFSET
    jb .read_ebadf
    sub rax, FD_OFFSET
    cmp rax, MAX_OPEN_FILES
    jae .read_ebadf

    ; Get handle from file table
    lea rcx, [file_table]
    mov rcx, [rcx + rax*8]
    test rcx, rcx
    jz .read_ebadf

    ; Call ReadFile(handle, buffer, count, &bytes_read, NULL)
    push rbx
    sub rsp, 56                     ; Shadow space + overlapped

    mov rdi, [rbp-16]               ; guest memory base
    mov rax, [rbx + 11*8]           ; a1 = buffer (guest addr)
    add rdi, rax                    ; host buffer address

    ; RCX already has handle
    mov rdx, rdi                    ; lpBuffer
    mov r8, [rbx + 12*8]            ; nNumberOfBytesToRead
    lea r9, [bytes_read_tmp]        ; lpNumberOfBytesRead
    mov qword [rsp+32], 0           ; lpOverlapped = NULL
    call ReadFile

    add rsp, 56
    pop rbx

    test ebx, ebx               ; Test rs1
    jz .read_error

    ; Return bytes read
    mov rax, [bytes_read_tmp]
    mov [rbx + 10*8], rax
    jmp .exec_loop

.read_eof:
    mov qword [rbx + 10*8], 0
    jmp .exec_loop

.read_error:
    mov qword [rbx + 10*8], -5      ; -EIO
    jmp .exec_loop

.read_ebadf:
    mov qword [rbx + 10*8], -9      ; -EBADF
    jmp .exec_loop

;------------------------------------------------------------------------------
; lseek(fd, offset, whence) - syscall 62
; a0 = fd, a1 = offset, a2 = whence (0=SEEK_SET, 1=SEEK_CUR, 2=SEEK_END)
; Returns new offset on success, negative errno on error
;------------------------------------------------------------------------------
.syscall_lseek:
    mov rax, [rbx + 10*8]           ; a0 = fd

    ; Check if it's a file fd
    cmp rax, FD_OFFSET
    jb .lseek_ebadf
    sub rax, FD_OFFSET
    cmp rax, MAX_OPEN_FILES
    jae .lseek_ebadf

    ; Get handle from file table
    lea rcx, [file_table]
    mov rcx, [rcx + rax*8]
    test rcx, rcx
    jz .lseek_ebadf

    ; Call SetFilePointer(handle, low_offset, &high_offset, whence)
    push rbx
    sub rsp, 48

    mov rax, [rbx + 11*8]           ; a1 = offset (64-bit)
    mov edx, eax                    ; lDistanceToMove (low 32 bits)
    shr rax, 32
    mov [rsp+32], eax               ; lpDistanceToMoveHigh

    mov r8, [rbx + 12*8]            ; a2 = whence
    ; Convert Linux whence to Windows
    ; Linux: SEEK_SET=0, SEEK_CUR=1, SEEK_END=2
    ; Windows: FILE_BEGIN=0, FILE_CURRENT=1, FILE_END=2
    ; They match!
    mov r9d, r8d                    ; dwMoveMethod

    lea r8, [rsp+32]                ; lpDistanceToMoveHigh
    ; RCX already has handle
    call SetFilePointer

    ; Check for error (INVALID_SET_FILE_POINTER with GetLastError != 0)
    cmp eax, -1
    je .lseek_check_error

    ; Combine low and high parts
    mov ecx, [rsp+32]               ; high part
    shl rcx, 32
    or rax, rcx                     ; full 64-bit offset

    add rsp, 48
    pop rbx
    mov [rbx + 10*8], rax
    jmp .exec_loop

.lseek_check_error:
    ; For simplicity, assume error if low part is -1
    add rsp, 48
    pop rbx
    mov qword [rbx + 10*8], -22     ; -EINVAL
    jmp .exec_loop

.lseek_ebadf:
    mov qword [rbx + 10*8], -9      ; -EBADF
    jmp .exec_loop

;------------------------------------------------------------------------------
; write(fd, buf, count) - syscall 64
; a0 = fd, a1 = buf (guest addr), a2 = count
; Returns bytes written, or negative errno
;------------------------------------------------------------------------------
.syscall_write:
    ; Get fd
    mov rax, [rbx + 10*8]       ; a0 = fd
    cmp rax, 1
    je .write_stdout
    cmp rax, 2
    je .write_stdout            ; stderr -> stdout for now

    ; Unsupported fd
    mov qword [rbx + 10*8], -9  ; -EBADF
    jmp .exec_loop

.write_stdout:
    ; Get buffer address (guest) and count
    mov rsi, [rbx + 11*8]       ; a1 = buf (guest offset)
    mov r8, [rbx + 12*8]        ; a2 = count (use r8 for Windows call)

    ; Convert guest address to host address
    mov rdi, [rbp-16]           ; guest memory base
    add rsi, rdi                ; RSI = host address of buffer

    ; Save rbx and count across Windows call
    push rbx
    push r8                     ; Save count

    ; Call Windows WriteFile(stdout_handle, buf, count, &written, NULL)
    ; RCX = handle, RDX = buffer, R8 = count, R9 = &written
    sub rsp, 48                 ; Shadow space + 5th arg
    mov rcx, [stdout_handle]
    mov rdx, rsi                ; buffer
    ; r8 already has count
    lea r9, [bytes_written]
    mov qword [rsp+32], 0       ; lpOverlapped = NULL
    call WriteFile

    add rsp, 48
    pop rax                     ; Restore count (return value)
    pop rbx                     ; Restore rbx

    mov [rbx + 10*8], rax       ; Return bytes written
    jmp .exec_loop

;------------------------------------------------------------------------------
; brk(addr) - syscall 214
; a0 = new break address (0 = query current)
; Returns current/new break address, or -1 on error
;------------------------------------------------------------------------------
.syscall_brk:
    ; Simple brk implementation using a static heap pointer
    ; Heap starts at end of loaded segments (we'll use a fixed address for now)
    ;
    ; If a0 == 0: return current break
    ; If a0 > current: extend break (if within limits)
    ; If a0 < current: shrink break

    mov rax, [rbx + 10*8]       ; a0 = requested break

    ; Get current break from a reserved location
    ; We'll store it at guest_memory + 0xF000 (near end of 64KB)
    mov rdi, [rbp-16]           ; guest memory base
    mov rcx, [rdi + 0xF000]     ; current break

    ; If break not initialized, set to 0x10000 (after typical code)
    test rcx, rcx
    jnz .brk_initialized
    mov rcx, 0x10000            ; Initial heap at 64KB
    mov [rdi + 0xF000], rcx

.brk_initialized:
    ; If a0 == 0, just return current break
    test rax, rax
    jz .brk_return_current

    ; Check if new break is valid
    cmp rax, 0x10000            ; Must be >= 64KB (heap starts here)
    jb .brk_return_current      ; Too low, return current
    cmp rax, 0x6000000          ; Must be < 96MB (leave room for stack)
    ja .brk_return_current      ; Too high, return current

    ; Set new break
    mov [rdi + 0xF000], rax
    mov [rbx + 10*8], rax       ; Return new break
    jmp .exec_loop

.brk_return_current:
    mov [rbx + 10*8], rcx       ; Return current break
    jmp .exec_loop

;------------------------------------------------------------------------------
; mmap(addr, len, prot, flags, fd, offset) - syscall 222
; For anonymous mappings only (fd=-1, MAP_ANONYMOUS)
; Returns mapped address, or negative errno
;------------------------------------------------------------------------------
.syscall_mmap:
    ; Check if this is anonymous mapping (fd == -1 or 0xFFFFFFFF)
    mov rax, [rbx + 14*8]       ; a4 = fd
    cmp rax, -1
    jne .mmap_enodev

    ; For anonymous mappings, just bump the break
    ; This is a simplification - real mmap would be more complex
    mov rdi, [rbp-16]           ; guest memory base
    mov rcx, [rdi + 0xF000]     ; current break

    ; If not initialized, init it
    test rcx, rcx
    jnz .mmap_have_break
    mov rcx, 0x10000
    mov [rdi + 0xF000], rcx

.mmap_have_break:
    ; Allocate len bytes
    mov rax, [rbx + 11*8]       ; a1 = len

    ; Check if fits (within 96MB limit)
    mov rdx, rcx
    add rdx, rax
    cmp rdx, 0x6000000
    ja .mmap_enomem

    ; Return current break as mapped address
    mov [rbx + 10*8], rcx

    ; Update break
    mov [rdi + 0xF000], rdx
    jmp .exec_loop

.mmap_enodev:
    mov qword [rbx + 10*8], -19 ; -ENODEV (no file mappings)
    jmp .exec_loop

.mmap_enomem:
    mov qword [rbx + 10*8], -12 ; -ENOMEM
    jmp .exec_loop

;------------------------------------------------------------------------------
; ioctl(fd, request, ...) - syscall 29
; a0 = fd, a1 = request, a2 = arg
; Returns 0 on success, negative errno on error
;------------------------------------------------------------------------------
.syscall_ioctl:
    mov rax, [rbx + 10*8]       ; a0 = fd
    mov rcx, [rbx + 11*8]       ; a1 = request

    ; Only support stdin/stdout/stderr
    cmp rax, 2
    ja .ioctl_ebadf

    ; TIOCGWINSZ (0x5413) - get window size
    ; Return something sensible for terminals
    cmp rcx, 0x5413
    jne .ioctl_enotty

    ; Write a fake winsize struct to the buffer
    ; struct winsize { uint16_t ws_row, ws_col, ws_xpixel, ws_ypixel; }
    mov rdi, [rbp-16]           ; guest memory base
    mov rax, [rbx + 12*8]       ; a2 = arg (guest address)
    add rdi, rax                ; host address

    mov word [rdi], 24          ; ws_row = 24
    mov word [rdi+2], 80        ; ws_col = 80
    mov word [rdi+4], 0         ; ws_xpixel = 0
    mov word [rdi+6], 0         ; ws_ypixel = 0

    mov qword [rbx + 10*8], 0   ; success
    jmp .exec_loop

.ioctl_enotty:
    mov qword [rbx + 10*8], -25 ; -ENOTTY
    jmp .exec_loop

.ioctl_ebadf:
    mov qword [rbx + 10*8], -9  ; -EBADF
    jmp .exec_loop

;------------------------------------------------------------------------------
; Stub syscalls that just return success
;------------------------------------------------------------------------------
.syscall_stub_success:
    mov qword [rbx + 10*8], 0
    jmp .exec_loop

.syscall_stub_error:
    mov qword [rbx + 10*8], -2      ; -ENOENT
    jmp .exec_loop

;------------------------------------------------------------------------------
; faccessat - syscall 48
; Check file accessibility (simplified: always return success)
;------------------------------------------------------------------------------
.syscall_faccessat:
    mov qword [rbx + 10*8], 0       ; Return success
    jmp .exec_loop

;------------------------------------------------------------------------------
; getcwd - syscall 17
; Get current working directory
;------------------------------------------------------------------------------
.syscall_getcwd:
    ; Just return "/" as current directory
    mov rdi, [rbp-16]               ; guest memory base
    mov rax, [rbx + 10*8]           ; a0 = buffer (guest addr)
    add rdi, rax
    mov byte [rdi], '/'
    mov byte [rdi+1], 0
    mov qword [rbx + 10*8], 1       ; Return length
    jmp .exec_loop

;------------------------------------------------------------------------------
; fstatat - syscall 79
; Get file status
;------------------------------------------------------------------------------
.syscall_fstatat:
    ; For now, return error - file not found
    mov qword [rbx + 10*8], -2      ; -ENOENT
    jmp .exec_loop

;------------------------------------------------------------------------------
; writev - syscall 66
; Write from multiple buffers (iovec)
; a0 = fd, a1 = iov (guest addr), a2 = iovcnt
;------------------------------------------------------------------------------
.syscall_writev:
    push r12
    push r13
    push r14
    sub rsp, 56

    ; Debug: Check what fd we're writing to
    mov rax, [rbx + 10*8]           ; fd
    cmp rax, 2
    jne .writev_not_stderr

    ; It's stderr - print "ERR:" prefix
    push rbx
    sub rsp, 40
    mov byte [num_buffer], 'E'
    mov byte [num_buffer+1], 'R'
    mov byte [num_buffer+2], 'R'
    mov byte [num_buffer+3], ':'
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 4
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 40
    pop rbx

.writev_not_stderr:
    mov r12, [rbx + 11*8]           ; a1 = iov pointer (guest)
    add r12, [rbp-16]               ; Convert to host addr
    mov r13d, [rbx + 12*8]          ; a2 = iovcnt
    xor r14d, r14d                  ; Total bytes written

    ; Get appropriate handle (stdout=1, stderr=2)
    mov rax, [rbx + 10*8]           ; fd
    cmp rax, 1
    je .writev_stdout
    cmp rax, 2
    je .writev_stderr
    ; Unknown fd - return error
    mov qword [rbx + 10*8], -9      ; -EBADF
    jmp .writev_done

.writev_stdout:
    mov rcx, [stdout_handle]
    jmp .writev_loop

.writev_stderr:
    ; For now, use stdout for stderr too
    mov rcx, [stdout_handle]

.writev_loop:
    test r13d, r13d
    jz .writev_success

    ; Get iov_base and iov_len
    mov rdi, [r12]                  ; iov_base (guest addr)
    add rdi, [rbp-16]               ; Convert to host
    mov rsi, [r12 + 8]              ; iov_len

    ; WriteFile(handle, buffer, count, &written, NULL)
    mov [rsp+48], rcx               ; Save handle
    mov rdx, rdi                    ; buffer
    mov r8, rsi                     ; count
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile
    mov rcx, [rsp+48]               ; Restore handle

    ; Add bytes written to total
    add r14d, [bytes_written]

    ; Next iovec (16 bytes each)
    add r12, 16
    dec r13d
    jmp .writev_loop

.writev_success:
    mov [rbx + 10*8], r14           ; Return total bytes written

.writev_done:
    add rsp, 56
    pop r14
    pop r13
    pop r12
    jmp .exec_loop

;------------------------------------------------------------------------------
; set_tid_address - syscall 96
;------------------------------------------------------------------------------
.syscall_set_tid_address:
    mov qword [rbx + 10*8], 1       ; Return fake TID
    jmp .exec_loop

;------------------------------------------------------------------------------
; getpid/gettid - syscall 172/178
;------------------------------------------------------------------------------
.syscall_getpid:
    mov qword [rbx + 10*8], 1       ; Fake PID
    jmp .exec_loop

;------------------------------------------------------------------------------
; getuid/geteuid/getgid/getegid - syscall 174-177
;------------------------------------------------------------------------------
.syscall_getuid:
    mov qword [rbx + 10*8], 1000    ; Fake UID
    jmp .exec_loop

;------------------------------------------------------------------------------
; uname - syscall 160
; a0 = struct utsname* (guest addr)
;------------------------------------------------------------------------------
.syscall_uname:
    mov rdi, [rbp-16]               ; guest memory base
    mov rax, [rbx + 10*8]           ; a0 = buf (guest addr)
    add rdi, rax                    ; host address

    ; struct utsname has 6 65-byte fields
    ; sysname, nodename, release, version, machine, domainname
    ; Just fill with minimal data
    mov byte [rdi], 'L'
    mov byte [rdi+1], 'i'
    mov byte [rdi+2], 'n'
    mov byte [rdi+3], 'u'
    mov byte [rdi+4], 'x'
    mov byte [rdi+5], 0

    ; nodename at +65
    mov byte [rdi+65], 'c'
    mov byte [rdi+66], 'o'
    mov byte [rdi+67], 'n'
    mov byte [rdi+68], 'w'
    mov byte [rdi+69], 'a'
    mov byte [rdi+70], 'y'
    mov byte [rdi+71], 0

    ; release at +130
    mov byte [rdi+130], '6'
    mov byte [rdi+131], '.'
    mov byte [rdi+132], '1'
    mov byte [rdi+133], '.'
    mov byte [rdi+134], '0'
    mov byte [rdi+135], 0

    ; version at +195
    mov byte [rdi+195], '#'
    mov byte [rdi+196], '1'
    mov byte [rdi+197], 0

    ; machine at +260
    mov byte [rdi+260], 'r'
    mov byte [rdi+261], 'i'
    mov byte [rdi+262], 's'
    mov byte [rdi+263], 'c'
    mov byte [rdi+264], 'v'
    mov byte [rdi+265], '6'
    mov byte [rdi+266], '4'
    mov byte [rdi+267], 0

    mov qword [rbx + 10*8], 0
    jmp .exec_loop

;------------------------------------------------------------------------------
; prlimit64 - syscall 261
; Just return success
;------------------------------------------------------------------------------
.syscall_prlimit64:
    mov qword [rbx + 10*8], 0
    jmp .exec_loop

;------------------------------------------------------------------------------
; getrandom - syscall 278
; a0 = buf, a1 = buflen, a2 = flags
; Fill with deterministic "random" data
;------------------------------------------------------------------------------
.syscall_getrandom:
    mov rdi, [rbp-16]               ; guest memory base
    mov rax, [rbx + 10*8]           ; a0 = buf (guest addr)
    add rdi, rax                    ; host address
    mov rcx, [rbx + 11*8]           ; a1 = buflen

    ; Fill with simple pattern
    xor eax, eax
.random_loop:
    test rcx, rcx
    jz .random_done
    mov byte [rdi], al
    inc al
    inc rdi
    dec rcx
    jmp .random_loop
.random_done:
    mov rax, [rbx + 11*8]           ; Return buflen
    mov [rbx + 10*8], rax
    jmp .exec_loop

;------------------------------------------------------------------------------
; futex - syscall 98
; Just return success (we're single-threaded)
;------------------------------------------------------------------------------
.syscall_futex:
    mov qword [rbx + 10*8], 0
    jmp .exec_loop

;------------------------------------------------------------------------------
; openat(dirfd, pathname, flags, mode) - syscall 56
; a0 = dirfd (-100 = AT_FDCWD), a1 = pathname, a2 = flags, a3 = mode
; Returns fd on success, negative errno on error
;------------------------------------------------------------------------------
.syscall_openat:
    push rbx
    sub rsp, 80                     ; Shadow space + locals

    ; Get pathname from guest memory
    mov rdi, [rbp-16]               ; guest memory base
    mov rax, [rbx + 11*8]           ; a1 = pathname (guest addr)
    add rdi, rax                    ; RDI = host addr of pathname

    ; Copy pathname to buffer (null-terminated)
    lea rsi, [path_buffer]
    mov ecx, 259
.copy_path:
    mov al, [rdi]
    mov [rsi], al
    test al, al
    jz .path_done
    inc rdi
    inc rsi
    dec ecx
    jnz .copy_path
    mov byte [rsi], 0
.path_done:

    ; Debug: print path being opened
    push rbx
    sub rsp, 48
    mov rcx, [stdout_handle]
    lea rdx, [path_buffer]
    ; Get string length
    xor r8d, r8d
    lea r11, [path_buffer]
.path_len:
    cmp byte [r11 + r8], 0
    je .path_len_done
    inc r8d
    cmp r8d, 250
    jb .path_len
.path_len_done:
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rbx

    ; Find a free slot in file table
    xor eax, eax
    lea r10, [file_table]           ; R10 = file table base
.find_slot:
    cmp eax, MAX_OPEN_FILES
    jge .openat_emfile
    mov rcx, [r10 + rax*8]
    test rcx, rcx
    jz .found_slot
    inc eax
    jmp .find_slot

.found_slot:
    push rax                        ; Save slot index
    push r10                        ; Save file table base

    ; Call CreateFileA
    ; RCX = lpFileName
    ; RDX = dwDesiredAccess
    ; R8 = dwShareMode
    ; R9 = lpSecurityAttributes
    ; [rsp+32] = dwCreationDisposition
    ; [rsp+40] = dwFlagsAndAttributes
    ; [rsp+48] = hTemplateFile
    lea rcx, [path_buffer]
    mov edx, GENERIC_READ
    mov r8d, FILE_SHARE_READ
    xor r9d, r9d
    mov qword [rsp+48], OPEN_EXISTING
    mov qword [rsp+56], FILE_ATTRIBUTE_NORMAL
    mov qword [rsp+64], 0
    call CreateFileA

    pop r10                         ; Restore file table base
    pop rcx                         ; Restore slot index
    cmp rax, INVALID_HANDLE_VALUE
    je .openat_enoent

    ; Store handle in file table
    mov [r10 + rcx*8], rax

    ; Return fd = slot + FD_OFFSET
    add ecx, FD_OFFSET
    add rsp, 80
    pop rbx
    mov [rbx + 10*8], rcx
    jmp .exec_loop

.openat_emfile:
    add rsp, 80
    pop rbx
    mov qword [rbx + 10*8], -24     ; -EMFILE (too many open files)
    jmp .exec_loop

.openat_enoent:
    add rsp, 80
    pop rbx
    mov qword [rbx + 10*8], -2      ; -ENOENT
    jmp .exec_loop

;------------------------------------------------------------------------------
; close(fd) - syscall 57
; a0 = fd
; Returns 0 on success, negative errno on error
;------------------------------------------------------------------------------
.syscall_close:
    mov rax, [rbx + 10*8]           ; a0 = fd

    ; Don't close stdin/stdout/stderr
    cmp rax, 2
    jbe .close_success

    ; Check if it's a valid fd
    sub rax, FD_OFFSET
    cmp rax, MAX_OPEN_FILES
    jae .close_success              ; Invalid fd, just return success

    ; Get handle from file table
    lea r10, [file_table]
    mov rcx, [r10 + rax*8]
    test rcx, rcx
    jz .close_success               ; Not open, return success

    ; Clear file table entry
    mov qword [r10 + rax*8], 0

    ; Call CloseHandle
    sub rsp, 40
    call CloseHandle
    add rsp, 40

.close_success:
    mov qword [rbx + 10*8], 0
    jmp .exec_loop

;------------------------------------------------------------------------------
; fstat(fd, statbuf) - syscall 80
; a0 = fd, a1 = statbuf (guest address)
; Returns 0 on success, negative errno on error
;------------------------------------------------------------------------------
.syscall_fstat:
    mov rax, [rbx + 10*8]       ; a0 = fd

    ; Only support stdin/stdout/stderr
    cmp rax, 2
    ja .fstat_ebadf

    ; Write a minimal stat struct for a character device (terminal)
    ; RISC-V Linux stat struct (LP64):
    ; struct stat {
    ;   uint64_t st_dev;          // 0
    ;   uint64_t st_ino;          // 8
    ;   uint32_t st_mode;         // 16
    ;   uint32_t st_nlink;        // 20
    ;   uint32_t st_uid;          // 24
    ;   uint32_t st_gid;          // 28
    ;   uint64_t st_rdev;         // 32
    ;   uint64_t __pad1;          // 40
    ;   int64_t  st_size;         // 48
    ;   int32_t  st_blksize;      // 56
    ;   int32_t  __pad2;          // 60
    ;   int64_t  st_blocks;       // 64
    ;   ... timespec fields ...   // 72+
    ; }

    mov rdi, [rbp-16]           ; guest memory base
    mov rcx, [rbx + 11*8]       ; a1 = statbuf (guest address)
    add rdi, rcx                ; host address

    ; Zero the struct first (128 bytes should cover it)
    push rdi
    xor eax, eax
    mov ecx, 16                 ; 16 qwords = 128 bytes
.fstat_zero:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .fstat_zero
    pop rdi

    ; Fill in key fields
    mov qword [rdi], 0x0005     ; st_dev = 5 (tty)
    mov qword [rdi+8], 1        ; st_ino = 1
    mov dword [rdi+16], 0x2190  ; st_mode = S_IFCHR | 0600 (character device)
    mov dword [rdi+20], 1       ; st_nlink = 1
    mov qword [rdi+32], 0x0501  ; st_rdev = makedev(5, 1) for /dev/console
    mov dword [rdi+56], 1024    ; st_blksize = 1024

    mov qword [rbx + 10*8], 0   ; success
    jmp .exec_loop

.fstat_ebadf:
    mov qword [rbx + 10*8], -9  ; -EBADF
    jmp .exec_loop

;------------------------------------------------------------------------------
; Conway syscall 1000: DG_DrawFrame
; Flush framebuffer to host display
; Currently a stub - just returns 0
;------------------------------------------------------------------------------
.syscall_drawframe:
    ; For now, just count frames
    ; TODO: Actually display framebuffer to Windows window
    mov qword [rbx + 10*8], 0   ; Return success
    jmp .exec_loop

;------------------------------------------------------------------------------
; Conway syscall 1001: DG_SleepMs(ms)
; a0 = milliseconds to sleep
;------------------------------------------------------------------------------
.syscall_sleepms:
    ; Get ms from a0
    mov rcx, [rbx + 10*8]       ; a0 = ms

    ; Save registers across Windows call
    push rbx
    sub rsp, 32                 ; Shadow space

    ; Call Windows Sleep(ms)
    ; RCX already has ms
    call Sleep

    add rsp, 32
    pop rbx

    ; Return 0 (success)
    mov qword [rbx + 10*8], 0
    jmp .exec_loop

.null_pc_error:
    ; PC became NULL - bad return address / function pointer
    ; Print "NULL! a0=XX ra=XX" for debugging
    mov rbx, [rbp-24]               ; Get rv_regs pointer
    push rbx
    sub rsp, 48

    mov byte [num_buffer], 'N'
    mov byte [num_buffer+1], 'U'
    mov byte [num_buffer+2], 'L'
    mov byte [num_buffer+3], 'L'
    mov byte [num_buffer+4], '!'
    mov byte [num_buffer+5], ' '
    mov byte [num_buffer+6], 'a'
    mov byte [num_buffer+7], '0'
    mov byte [num_buffer+8], '='

    ; Print a0 (x10) in hex (8 digits)
    mov rax, [rbx + 10*8]           ; a0
    lea rdi, [num_buffer+9]
    mov ecx, 8
.npc_a0_loop:
    rol eax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .npc_a0_dig
    add dl, 'A'-10
    jmp .npc_a0_str
.npc_a0_dig:
    add dl, '0'
.npc_a0_str:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .npc_a0_loop

    mov byte [rdi], 13
    mov byte [rdi+1], 10

    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 19
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rbx
    jmp .done

.xlate_failed:
    ; Debug: print "X" to indicate translation failure
    push rax
    sub rsp, 48
    mov byte [num_buffer], 'X'
    mov byte [num_buffer+1], 13
    mov byte [num_buffer+2], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 3
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rax

.done:
    ; Debug: just print "!"
    sub rsp, 48
    mov byte [num_buffer], '!'
    mov byte [num_buffer+1], 13
    mov byte [num_buffer+2], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 3
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48

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

