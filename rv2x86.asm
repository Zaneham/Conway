; rv2x86.asm
; RISC-V to x86-64 binary translator
; Because someone had to
;
; Named after Lynn Conway - pioneer of dynamic instruction handling

bits 64
default rel

section .data
    ; Test: addi a0, zero, 42 = 0x02a00513
    ; Encoding: imm[11:0]=42 | rs1=0 | funct3=0 | rd=10 | opcode=0x13
    test_instruction: dd 0x02a00513

section .bss
    ; Buffer for emitted x86-64 code
    code_buffer: resb 4096

    ; RISC-V register file (x0-x31, 64-bit each)
    rv_regs: resq 32

section .text
global _start

;--------------------------------------------------
; Entry point
;--------------------------------------------------
_start:
    ; Initialise register file (x0 is always 0)
    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 256                ; 32 * 8 bytes
    rep stosb

    ; Load test instruction
    mov edi, [test_instruction]

    ; Translate it
    lea rsi, [code_buffer]      ; output buffer
    call translate_instruction
    ; RAX = bytes written

    ; Append RET to translated code
    lea rdi, [code_buffer]
    add rdi, rax
    mov byte [rdi], 0xC3        ; ret

    ; Make buffer executable (mprotect)
    lea rdi, [code_buffer]
    and rdi, ~0xFFF             ; page align
    mov rsi, 4096               ; length
    mov rdx, 7                  ; PROT_READ|WRITE|EXEC
    mov rax, 10                 ; sys_mprotect
    syscall

    ; Call translated code
    ; RBX = pointer to register file for translated code
    lea rbx, [rv_regs]
    lea rax, [code_buffer]
    call rax

    ; Result is in rv_regs[10] (a0)
    lea rax, [rv_regs]
    mov eax, [rax + 10*8]       ; load a0 (rd=10)

    ; Exit with it
    mov edi, eax
    mov eax, 60                 ; sys_exit
    syscall

;--------------------------------------------------
; translate_instruction
; Input:  EDI = RISC-V instruction
;         RSI = output buffer pointer
; Output: RAX = bytes written
;--------------------------------------------------
translate_instruction:
    push rbx
    push r12
    push r13
    mov r12, rsi                ; save output pointer
    mov r13, rdi                ; save instruction

    ; Extract opcode (bits 6:0)
    mov eax, edi
    and eax, 0x7F

    ; Dispatch on opcode
    cmp eax, 0x13               ; OP-IMM (addi, slti, etc.)
    je .op_imm

    cmp eax, 0x33               ; OP (add, sub, etc.)
    je .op_reg

    cmp eax, 0x37               ; LUI
    je .lui

    ; Unknown opcode - emit INT3 for debugging
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;--------------------------------------------------
; OP-IMM: Register-Immediate operations
;--------------------------------------------------
.op_imm:
    ; Extract funct3 (bits 14:12) to determine operation
    mov eax, r13d
    shr eax, 12
    and eax, 0x7

    cmp eax, 0x0                ; ADDI
    je .addi
    cmp eax, 0x1                ; SLLI
    je .slli
    cmp eax, 0x2                ; SLTI
    je .slti
    cmp eax, 0x3                ; SLTIU
    je .sltiu
    cmp eax, 0x4                ; XORI
    je .xori
    cmp eax, 0x5                ; SRLI/SRAI
    je .srli_srai
    cmp eax, 0x6                ; ORI
    je .ori
    cmp eax, 0x7                ; ANDI
    je .andi

    ; Unknown funct3
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;--------------------------------------------------
; ADDI rd, rs1, imm
;--------------------------------------------------
.addi:
    ; Extract fields
    call extract_i_type         ; rd in ECX, rs1 in EBX, imm in EAX

    ; Skip if rd == x0 (writes to x0 are discarded)
    test ecx, ecx
    jz .emit_nop

    ; Special case: rs1 == x0 means load immediate (pseudo: li rd, imm)
    test ebx, ebx
    jz .emit_li

    ; General case: rd = rs1 + imm
    ; Emit: mov rax, [rbx + rs1*8]
    ;       add rax, imm32
    ;       mov [rbx + rd*8], rax

    ; mov rax, [rbx + rs1*8]  =>  48 8B 43 disp8  (if disp fits in 8 bits)
    mov byte [r12], 0x48        ; REX.W
    mov byte [r12+1], 0x8B      ; MOV r64, r/m64

    ; Calculate displacement (rs1 * 8)
    mov edx, ebx
    shl edx, 3
    cmp edx, 127
    ja .addi_disp32

    ; Use disp8
    mov byte [r12+2], 0x43      ; ModRM: [rbx + disp8], rax
    mov [r12+3], dl             ; disp8
    lea r12, [r12+4]
    jmp .addi_emit_add

.addi_disp32:
    mov byte [r12+2], 0x83      ; ModRM: [rbx + disp32], rax
    mov [r12+3], edx            ; disp32
    lea r12, [r12+7]

.addi_emit_add:
    ; add rax, imm32  =>  48 05 imm32  (or 48 83 C0 imm8 if small)
    push rcx                    ; save rd
    mov ecx, eax                ; imm in ecx

    ; Check if immediate fits in signed byte
    movsx edx, cl
    cmp edx, eax
    jne .addi_imm32

    ; Use imm8: add rax, imm8  =>  48 83 C0 imm8
    mov byte [r12], 0x48
    mov byte [r12+1], 0x83
    mov byte [r12+2], 0xC0
    mov [r12+3], cl
    lea r12, [r12+4]
    jmp .addi_emit_store

.addi_imm32:
    ; Use imm32: add rax, imm32  =>  48 05 imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], ecx
    lea r12, [r12+6]

.addi_emit_store:
    pop rcx                     ; restore rd

    ; mov [rbx + rd*8], rax
    mov byte [r12], 0x48        ; REX.W
    mov byte [r12+1], 0x89      ; MOV r/m64, r64

    mov edx, ecx
    shl edx, 3                  ; rd * 8
    cmp edx, 127
    ja .addi_store_disp32

    mov byte [r12+2], 0x43      ; ModRM: [rbx + disp8]
    mov [r12+3], dl
    lea r12, [r12+4]
    jmp .addi_done

.addi_store_disp32:
    mov byte [r12+2], 0x83      ; ModRM: [rbx + disp32]
    mov [r12+3], edx
    lea r12, [r12+7]

.addi_done:
    lea rax, [code_buffer]
    sub r12, rax
    mov rax, r12
    jmp .done

;--------------------------------------------------
; LI pseudo-instruction (ADDI rd, x0, imm)
;--------------------------------------------------
.emit_li:
    ; Emit: mov rax, imm32 (sign-extended)
    ;       mov [rbx + rd*8], rax

    ; mov rax, imm32  =>  48 C7 C0 imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC0
    mov [r12+3], eax            ; imm32

    ; mov [rbx + rd*8], rax
    mov byte [r12+7], 0x48
    mov byte [r12+8], 0x89

    mov edx, ecx
    shl edx, 3                  ; rd * 8
    cmp edx, 127
    ja .li_disp32

    mov byte [r12+9], 0x43      ; ModRM: [rbx + disp8]
    mov [r12+10], dl
    mov rax, 11
    jmp .done

.li_disp32:
    mov byte [r12+9], 0x83      ; ModRM: [rbx + disp32]
    mov [r12+10], edx
    mov rax, 14
    jmp .done

;--------------------------------------------------
; NOP (write to x0)
;--------------------------------------------------
.emit_nop:
    ; Emit single-byte NOP
    mov byte [r12], 0x90
    mov rax, 1
    jmp .done

;--------------------------------------------------
; Placeholder handlers for other I-type ops
;--------------------------------------------------
.slli:
.slti:
.sltiu:
.xori:
.srli_srai:
.ori:
.andi:
    ; TODO: Implement
    mov byte [r12], 0xCC        ; INT3
    mov rax, 1
    jmp .done

;--------------------------------------------------
; OP: Register-Register operations
;--------------------------------------------------
.op_reg:
    ; TODO: Implement ADD, SUB, etc.
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;--------------------------------------------------
; LUI: Load Upper Immediate
;--------------------------------------------------
.lui:
    ; TODO: Implement
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

.done:
    pop r13
    pop r12
    pop rbx
    ret

;--------------------------------------------------
; extract_i_type
; Input:  R13D = instruction
; Output: ECX = rd, EBX = rs1, EAX = immediate (sign-extended)
;--------------------------------------------------
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
    sar eax, 20                 ; arithmetic shift for sign extension

    ret
