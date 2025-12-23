; rv2x86_win.asm
; RISC-V to x86-64 binary translator - Windows version
; "Have you tried turning it off and on again?" - No, we're translating it.
;
; Named after Lynn Conway - pioneer of dynamic instruction handling
; A legend who had to rebuild her entire career. Absolute icon.

bits 64
default rel

;==============================================================================
; Constants - The boring but necessary bits
;==============================================================================
PAGE_EXECUTE_READWRITE equ 0x40
MEM_COMMIT             equ 0x1000
MEM_RESERVE            equ 0x2000

; RISC-V opcodes - These are the magic numbers
RV_OP_LUI       equ 0x37        ; Load Upper Immediate
RV_OP_AUIPC     equ 0x17        ; Add Upper Immediate to PC
RV_OP_OP_IMM    equ 0x13        ; Register-Immediate arithmetic
RV_OP_OP        equ 0x33        ; Register-Register arithmetic
RV_OP_LOAD      equ 0x03        ; Load instructions
RV_OP_STORE     equ 0x23        ; Store instructions

; Funct3 values for OP-IMM
RV_F3_ADDI      equ 0x0
RV_F3_SLTI      equ 0x2
RV_F3_SLTIU     equ 0x3
RV_F3_XORI      equ 0x4
RV_F3_ORI       equ 0x6
RV_F3_ANDI      equ 0x7
RV_F3_SLLI      equ 0x1
RV_F3_SRLI_SRAI equ 0x5         ; Differentiated by funct7

; Funct3 values for OP (same encoding, different context)
RV_F3_ADD_SUB   equ 0x0         ; Differentiated by funct7
RV_F3_SLL       equ 0x1
RV_F3_SLT       equ 0x2
RV_F3_SLTU      equ 0x3
RV_F3_XOR       equ 0x4
RV_F3_SRL_SRA   equ 0x5         ; Differentiated by funct7
RV_F3_OR        equ 0x6
RV_F3_AND       equ 0x7

; Funct7 values
RV_F7_NORMAL    equ 0x00        ; ADD, SRL, etc.
RV_F7_ALT       equ 0x20        ; SUB, SRA

; Funct3 values for loads
RV_F3_LB        equ 0x0         ; Load Byte (sign-extended)
RV_F3_LH        equ 0x1         ; Load Halfword (sign-extended)
RV_F3_LW        equ 0x2         ; Load Word (sign-extended)
RV_F3_LD        equ 0x3         ; Load Doubleword
RV_F3_LBU       equ 0x4         ; Load Byte Unsigned
RV_F3_LHU       equ 0x5         ; Load Halfword Unsigned
RV_F3_LWU       equ 0x6         ; Load Word Unsigned

; Funct3 values for stores
RV_F3_SB        equ 0x0         ; Store Byte
RV_F3_SH        equ 0x1         ; Store Halfword
RV_F3_SW        equ 0x2         ; Store Word
RV_F3_SD        equ 0x3         ; Store Doubleword

section .data
    ; Test instruction - we'll make this more sophisticated later
    ; addi a0, zero, 42 = 0x02a00513
    ; When this works, we know we haven't ballsed it up completely
    test_instruction: dd 0x02a00513

    ; Messages for the humans
    fmt: db "Result: %d", 10, 0

    ; A zero. Constant. Unchanging. Like my will to debug segfaults.
    zero: dq 0

section .bss
    ; Buffer for emitted x86-64 code
    ; 4K should be enough for anybody (famous last words)
    alignb 16
    code_buffer: resb 4096

    ; RISC-V register file (x0-x31, 64-bit each)
    ; x0 is hardwired to zero. Don't @ me, it's the spec.
    alignb 8
    rv_regs: resq 32

    ; Programme counter - because we need to know where we are
    rv_pc: resq 1

    ; Guest memory buffer - where RISC-V programmes live
    ; 64KB should handle most test cases. We can always allocate more later.
    ; "The thing about memory is, you always run out." - Every programmer ever
    alignb 4096
    rv_memory: resb 65536
    RV_MEMORY_SIZE equ 65536

    ; For VirtualProtect - Windows needs to know we're not up to mischief
    old_protect: resd 1

section .text
    global main
    global translate_instruction
    extern printf
    extern VirtualProtect
    extern ExitProcess

;==============================================================================
; Entry point
; This is where the magic happens. Or the crashes. Usually both.
;==============================================================================
main:
    push rbp
    mov rbp, rsp
    sub rsp, 64                 ; Shadow space - Windows is needy

    ; Zero out the register file
    ; "Did you see that ludicrous display last night?"
    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 256                ; 32 regs * 8 bytes
.clear_loop:
    mov [rdi], al
    inc rdi
    dec ecx
    jnz .clear_loop

    ; Initialise PC to zero
    mov qword [rv_pc], 0

    ; Load our test instruction
    mov edi, [test_instruction]

    ; Translate it - fingers crossed
    lea rsi, [code_buffer]
    call translate_instruction
    ; RAX = bytes written (or tears shed)

    ; Append RET so we come back home safely
    lea rdi, [code_buffer]
    add rdi, rax
    mov byte [rdi], 0xC3        ; ret - the "come back" instruction

    ; Make buffer executable
    ; VirtualProtect: "Are you sure?" Us: "Just do it."
    lea rcx, [code_buffer]
    mov rdx, 4096
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    ; Execute translated code
    ; RBX = pointer to register file (our translated code expects this)
    ; R14 = pointer to guest memory (for load/store instructions)
    lea rbx, [rv_regs]
    lea r14, [rv_memory]
    lea rax, [code_buffer]
    call rax

    ; Grab result from a0 (x10)
    lea rax, [rv_regs]
    mov eax, [rax + 10*8]

    ; Tell the world
    lea rcx, [fmt]
    mov edx, eax
    call printf

    ; Exit with the result as our status
    lea rax, [rv_regs]
    mov ecx, [rax + 10*8]
    call ExitProcess

;==============================================================================
; translate_instruction
; The heart of Conway. Decodes RISC-V, emits x86-64.
;
; Input:  EDI = 32-bit RISC-V instruction
;         RSI = output buffer pointer
; Output: RAX = bytes written
;
; Clobbers: Pretty much everything. It's assembly, what did you expect?
;==============================================================================
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

    cmp eax, RV_OP_LOAD
    je .load

    cmp eax, RV_OP_STORE
    je .store

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

    push rax
    call emit_load_rs1
    pop rax

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

    push rax
    call emit_load_rs1
    pop rax

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
; LOAD - Memory load operations
; "Memory is like a teenager's room. Everything's in there, you just have to
;  know where to look." - Ancient programmer wisdom
;
; All loads use I-type encoding: rd = mem[rs1 + imm]
; R14 points to guest memory base in translated code
;==============================================================================
.load:
    ; Extract funct3 to determine load size
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

    ; Unknown load funct3
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;==============================================================================
; LB - Load Byte (sign-extended)
; rd = signext(mem[rs1 + imm][7:0])
;==============================================================================
.lb:
    call extract_i_type         ; ECX = rd, EBX = rs1, EAX = imm

    test ecx, ecx
    jz .emit_nop

    ; Calculate address: rax = rv_regs[rs1] + imm
    push rcx                    ; Save rd
    push rax                    ; Save imm
    call emit_load_rs1          ; RAX = rs1 value
    pop rdx                     ; imm in RDX

    ; add rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    ; Now RAX = guest address. Load from [r14 + rax]
    ; movsx rax, byte [r14 + rax]
    ; REX.W 0F BE /r with ModRM for [r14 + rax]
    mov byte [r12], 0x49        ; REX.WB (W + B for R14)
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xBE      ; MOVSX r64, r/m8
    mov byte [r12+3], 0x04      ; ModRM: [SIB] with RAX
    mov byte [r12+4], 0x06      ; SIB: base=R14, index=RAX, scale=1
    add r12, 5

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LH - Load Halfword (sign-extended)
; rd = signext(mem[rs1 + imm][15:0])
;==============================================================================
.lh:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    ; add rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    ; movsx rax, word [r14 + rax]
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xBF      ; MOVSX r64, r/m16
    mov byte [r12+3], 0x04
    mov byte [r12+4], 0x06
    add r12, 5

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LW - Load Word (sign-extended for RV64)
; rd = signext(mem[rs1 + imm][31:0])
;==============================================================================
.lw:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    ; add rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    ; movsxd rax, dword [r14 + rax]
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0x63      ; MOVSXD r64, r/m32
    mov byte [r12+2], 0x04
    mov byte [r12+3], 0x06
    add r12, 4

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LD - Load Doubleword
; rd = mem[rs1 + imm][63:0]
;==============================================================================
.ld:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    ; add rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    ; mov rax, qword [r14 + rax]
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0x8B      ; MOV r64, r/m64
    mov byte [r12+2], 0x04
    mov byte [r12+3], 0x06
    add r12, 4

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LBU - Load Byte Unsigned
; rd = zeroext(mem[rs1 + imm][7:0])
;==============================================================================
.lbu:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    ; add rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    ; movzx rax, byte [r14 + rax]
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB6      ; MOVZX r64, r/m8
    mov byte [r12+3], 0x04
    mov byte [r12+4], 0x06
    add r12, 5

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LHU - Load Halfword Unsigned
; rd = zeroext(mem[rs1 + imm][15:0])
;==============================================================================
.lhu:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    ; add rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    ; movzx rax, word [r14 + rax]
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB7      ; MOVZX r64, r/m16
    mov byte [r12+3], 0x04
    mov byte [r12+4], 0x06
    add r12, 5

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LWU - Load Word Unsigned
; rd = zeroext(mem[rs1 + imm][31:0])
;==============================================================================
.lwu:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    ; add rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    ; mov eax, dword [r14 + rax]
    ; Using 32-bit dest automatically zero-extends to 64 bits
    mov byte [r12], 0x41        ; REX.B (for R14)
    mov byte [r12+1], 0x8B      ; MOV r32, r/m32
    mov byte [r12+2], 0x04
    mov byte [r12+3], 0x06
    add r12, 4

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; STORE - Memory store operations
; "Writing to memory is easy. Writing to the *correct* memory is hard."
;
; All stores use S-type encoding: mem[rs1 + imm] = rs2
;==============================================================================
.store:
    ; Extract funct3 to determine store size
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

    ; Unknown store funct3
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;==============================================================================
; SB - Store Byte
; mem[rs1 + imm] = rs2[7:0]
;==============================================================================
.sb:
    call extract_s_type         ; ECX = rs2, EBX = rs1, EAX = imm

    push rcx                    ; Save rs2
    push rax                    ; Save imm

    ; Load rs1 (base address)
    call emit_load_rs1          ; RAX = rs1 value

    pop rdx                     ; imm in RDX

    ; add rax, imm32 (calculate guest address)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    ; Now RAX = guest address
    ; Load rs2 into RCX
    pop rdx                     ; rs2 index
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B      ; MOV RCX, [rbx + disp8]
    shl edx, 3
    mov [r12+3], dl
    add r12, 4

    ; mov byte [r14 + rax], cl
    mov byte [r12], 0x41        ; REX.B (for R14)
    mov byte [r12+1], 0x88      ; MOV r/m8, r8
    mov byte [r12+2], 0x0C      ; ModRM: [SIB]
    mov byte [r12+3], 0x06      ; SIB: base=R14, index=RAX
    add r12, 4

    jmp .calc_size

;==============================================================================
; SH - Store Halfword
; mem[rs1 + imm] = rs2[15:0]
;==============================================================================
.sh:
    call extract_s_type

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    ; add rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    ; Load rs2 into RCX
    pop rdx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    shl edx, 3
    mov [r12+3], dl
    add r12, 4

    ; mov word [r14 + rax], cx
    mov byte [r12], 0x66        ; Operand size prefix
    mov byte [r12+1], 0x41      ; REX.B
    mov byte [r12+2], 0x89      ; MOV r/m16, r16
    mov byte [r12+3], 0x0C      ; ModRM: [SIB]
    mov byte [r12+4], 0x06      ; SIB
    add r12, 5

    jmp .calc_size

;==============================================================================
; SW - Store Word
; mem[rs1 + imm] = rs2[31:0]
;==============================================================================
.sw:
    call extract_s_type

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    ; add rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    ; Load rs2 into RCX
    pop rdx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    shl edx, 3
    mov [r12+3], dl
    add r12, 4

    ; mov dword [r14 + rax], ecx
    mov byte [r12], 0x41        ; REX.B
    mov byte [r12+1], 0x89      ; MOV r/m32, r32
    mov byte [r12+2], 0x0C      ; ModRM: [SIB]
    mov byte [r12+3], 0x06      ; SIB
    add r12, 4

    jmp .calc_size

;==============================================================================
; SD - Store Doubleword
; mem[rs1 + imm] = rs2[63:0]
;==============================================================================
.sd:
    call extract_s_type

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    ; add rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    ; Load rs2 into RCX
    pop rdx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    shl edx, 3
    mov [r12+3], dl
    add r12, 4

    ; mov qword [r14 + rax], rcx
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0x89      ; MOV r/m64, r64
    mov byte [r12+2], 0x0C      ; ModRM: [SIB]
    mov byte [r12+3], 0x06      ; SIB
    add r12, 4

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

;==============================================================================
; extract_s_type - S-type instruction format (stores)
; Input:  R13D = instruction
; Output: ECX = rs2 (source), EBX = rs1 (base), EAX = immediate (sign-extended)
; S-type: imm[11:5] rs2 rs1 funct3 imm[4:0] opcode
;==============================================================================
extract_s_type:
    ; rs1 = bits 19:15 (base register)
    mov eax, r13d
    shr eax, 15
    and eax, 0x1F
    mov ebx, eax

    ; rs2 = bits 24:20 (source register)
    mov eax, r13d
    shr eax, 20
    and eax, 0x1F
    mov ecx, eax

    ; imm = {imm[11:5], imm[4:0]}
    ; imm[4:0] = bits 11:7
    mov eax, r13d
    shr eax, 7
    and eax, 0x1F
    mov edx, eax

    ; imm[11:5] = bits 31:25
    mov eax, r13d
    sar eax, 20             ; Shift right, keeping sign in bit 11
    and eax, 0xFFFFFFE0     ; Clear lower 5 bits
    or eax, edx             ; Combine with lower bits

    ret
