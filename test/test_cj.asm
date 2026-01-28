; test_cj.asm - Test C.J (compressed jump) instruction
bits 64
default rel

extern init_block_cache
extern execute_blocks
extern code_buffer
extern ExitProcess
extern VirtualAlloc
extern VirtualProtect
extern GetStdHandle
extern WriteFile

PAGE_EXECUTE_READWRITE  equ 0x40
PAGE_READWRITE          equ 0x04
MEM_COMMIT              equ 0x1000
MEM_RESERVE             equ 0x2000
STD_OUTPUT_HANDLE       equ -11

section .data
    msg_test    db "Testing C.J...", 13, 10, 0
    msg_pass    db "PASS: C.J worked", 13, 10, 0
    msg_fail    db "FAIL: wrong a0", 13, 10, 0

section .bss
    old_protect     resd 1
    alignb 8
    guest_memory    resq 1
    stdout_handle   resq 1
    chars_written   resq 1
    rv_regs         resq 32
    rv_pc           resq 1

section .text
    global main

main:
    push rbp
    mov rbp, rsp
    sub rsp, 80

    ; Get stdout
    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [stdout_handle], rax

    ; Print test message
    mov rcx, [stdout_handle]
    lea rdx, [msg_test]
    mov r8d, 16
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Allocate guest memory
    xor ecx, ecx
    mov edx, 65536
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz .fail
    mov [guest_memory], rax

    ; Make code buffer executable
    lea rcx, [code_buffer]
    mov edx, 1048576
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    ; Init block cache
    call init_block_cache

    ; Write simple test code using C.J
    ; At 0x1000: C.LI a0, 10      ; a0 = 10
    ; At 0x1002: C.J +4           ; Jump forward 4 bytes (to 0x1006)
    ; At 0x1004: C.LI a0, 20      ; a0 = 20 (should be skipped)
    ; At 0x1006: C.LI a7, 93      ; a7 = 93 (but we can't fit 93 in 6 bits)
    ; We'll use addi a7, x0, 93 (32-bit)
    ;
    ; Actually C.J encoding is complex. Let me use a simple jump offset.
    ; C.J +4 = jump to PC+4
    ; C.J encoding: 101 | imm[11|4|9:8|10|6|7|3:1|5] | 01
    ; For offset +4: imm = 0b000000000100 = 4
    ; imm[11] = 0, imm[4] = 0, imm[9:8] = 00, imm[10] = 0
    ; imm[6] = 0, imm[7] = 0, imm[3:1] = 010, imm[5] = 0
    ; inst = 101 | 0 | 0 | 00 | 0 | 0 | 0 | 010 | 0 | 01
    ;      = 101_0_0_00_0_0_0_010_0_01 = 0b1010000001001 = 0xA009
    ; Wait, that's 13 bits. Let me recalculate.
    ;
    ; Bits: 15-13=funct3, 12=imm[11], 11=imm[4], 10:9=imm[9:8],
    ;       8=imm[10], 7=imm[6], 6=imm[7], 5:3=imm[3:1], 2=imm[5], 1:0=op
    ;
    ; For offset = 4 (imm[11:1] = 4/2 = 2 = 0b00000000010):
    ; Actually offset is already in bytes and bit 0 is always 0.
    ; So imm = offset with implied bit0 = 0.
    ; For offset 4: imm[11:0] = 4
    ; imm[11] = 0, imm[10] = 0, imm[9:8] = 00, imm[7] = 0, imm[6] = 0
    ; imm[5] = 0, imm[4] = 0, imm[3:1] = 010
    ;
    ; Encoding C.J with imm=4:
    ; bit 12 = imm[11] = 0
    ; bit 11 = imm[4] = 0
    ; bits 10:9 = imm[9:8] = 00
    ; bit 8 = imm[10] = 0
    ; bit 7 = imm[6] = 0
    ; bit 6 = imm[7] = 0
    ; bits 5:3 = imm[3:1] = 010
    ; bit 2 = imm[5] = 0
    ; bits 1:0 = 01
    ; funct3 = 101
    ; Full: 101_0_0_00_0_0_0_010_0_01 = 0b1010000001001001 = 0xA009
    ;
    ; Hmm let me use a simpler approach - just test if jump lands correctly

    mov rdi, [guest_memory]

    ; At 0x1000: li a0, 42 (32-bit)
    ; addi a0, x0, 42 = 0x02A00513
    mov dword [rdi + 0x1000], 0x02A00513

    ; At 0x1004: C.J +6 (jump to 0x100A)
    ; This jumps over the next instruction at 0x1006-0x1009
    ; offset = 6, imm[11:0] = 6 = 0b000000000110
    ; imm[11]=0, imm[10]=0, imm[9:8]=00, imm[7]=0, imm[6]=0
    ; imm[5]=0, imm[4]=0, imm[3:1]=011
    ;
    ; C.J encoding (16 bits):
    ; bits 15:13 = funct3 = 101
    ; bit 12 = imm[11] = 0
    ; bit 11 = imm[4] = 0
    ; bits 10:9 = imm[9:8] = 00
    ; bit 8 = imm[10] = 0
    ; bit 7 = imm[6] = 0
    ; bit 6 = imm[7] = 0
    ; bits 5:3 = imm[3:1] = 011
    ; bit 2 = imm[5] = 0
    ; bits 1:0 = opcode = 01
    ; = 101_0_0_00_0_0_0_011_0_01 = 0b1010000000011001 = 0xA019
    mov word [rdi + 0x1004], 0xA019

    ; At 0x1006: li a0, 99 (32-bit) - should be SKIPPED
    ; addi a0, x0, 99 = 0x06300513
    mov dword [rdi + 0x1006], 0x06300513

    ; At 0x100A: addi a7, x0, 93 = exit syscall
    mov dword [rdi + 0x100A], 0x05D00893

    ; At 0x100E: ecall
    mov dword [rdi + 0x100E], 0x00000073

    ; Clear registers
    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 32
.clr:
    mov [rdi + rcx*8 - 8], rax
    dec ecx
    jnz .clr

    ; Execute starting at PC 0x1000
    mov edi, 0x1000
    mov rsi, [guest_memory]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8d, 10
    call execute_blocks

    ; Check a0 - should be 42 (not 99)
    lea rax, [rv_regs]
    mov ecx, [rax + 10*8]
    cmp ecx, 42
    jne .wrong_value

    ; Print pass
    mov rcx, [stdout_handle]
    lea rdx, [msg_pass]
    mov r8d, 18
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile
    mov ecx, 0
    jmp .exit

.wrong_value:
    mov rcx, [stdout_handle]
    lea rdx, [msg_fail]
    mov r8d, 16
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile
    mov ecx, 1
    jmp .exit

.fail:
    mov ecx, 255

.exit:
    add rsp, 80
    pop rbp
    sub rsp, 40
    call ExitProcess
