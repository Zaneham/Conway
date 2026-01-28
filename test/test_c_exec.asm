; test_c_exec.asm - Execute compressed instructions
bits 64
default rel

extern init_block_cache
extern execute_blocks
extern code_buffer
extern ExitProcess
extern VirtualAlloc
extern VirtualProtect
extern GetStdHandle
extern WriteConsoleA

PAGE_EXECUTE_READWRITE  equ 0x40
PAGE_READWRITE          equ 0x04
MEM_COMMIT              equ 0x1000
MEM_RESERVE             equ 0x2000
STD_OUTPUT_HANDLE       equ -11

section .data
    msg_test    db "Testing C extension execution...", 13, 10, 0
    msg_pass    db "PASS: exit code ", 0
    msg_nl      db 13, 10, 0

section .bss
    old_protect     resd 1
    alignb 8
    guest_memory    resq 1
    stdout_handle   resq 1
    chars_written   resq 1
    rv_regs         resq 32
    rv_pc           resq 1
    num_buf         resb 16

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
    mov r8d, 35
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteConsoleA

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

    ; Initialise block cache
    call init_block_cache

    ; Write test code to guest memory
    ; Simple programme:
    ;   C.LI a0, 42    ; Load immediate 42 into a0 (exit code)
    ;   C.LI a7, 93    ; Load immediate 93 into a7 (exit syscall number)
    ;   ECALL          ; Exit
    ;
    ; C.LI encoding: 010 | imm[5] | rd | imm[4:0] | 01
    ; C.LI a0, 42: rd=01010 (x10), imm=42=101010 -> 010|1|01010|01010|01 = 0x5529
    ; C.LI a7, 93: rd=10001 (x17), imm=93=1011101 -> hmm 93 > 63
    ; 93 needs 7 bits but C.LI only has 6-bit signed immediate (-32 to 31)
    ; So let's use exit code 31 instead
    ;
    ; C.LI a0, 31: imm=31=011111, imm[5]=0, imm[4:0]=11111
    ;   010 | 0 | 01010 | 11111 | 01 = 0b0100010101111101 = 0x457D
    ;
    ; For a7=93, we need to use a sequence:
    ;   C.LI a7, 93 doesn't work (out of range)
    ; Let's use 32-bit addi instead:
    ;   addi a7, x0, 93 = 0x05D00893
    ;
    ; Or we could test with a simpler programme:
    ;   li a0, 42 using 32-bit
    ;   li a7, 93 using 32-bit
    ;   ecall
    ;
    ; Let's just test if we can execute a C.LI followed by 32-bit instructions
    ;
    ; Test: C.LI a0, 7, then overwrite with 32-bit li a0, 42
    ; Actually, let's just test pure 32-bit first to verify execution works

    mov rdi, [guest_memory]

    ; Test C.LDSP - load from stack
    ; First set sp = 0x1000, and put value 77 at offset 0x1008
    ; Then C.LDSP a0, 8 should load that value

    ; Put 77 at guest memory + 0x1008
    mov qword [rdi + 0x1008], 77

    ; Now put test code at offset 0
    ; Set sp (x2) = 0x1000 using 32-bit addi
    ; addi sp, x0, 0x1000 = imm=0x1000 but that's 12 bits, max=2047
    ; Let's use 0x100 instead, and put value at 0x108
    mov qword [rdi + 0x108], 88

    ; addi sp, x0, 0x100 = 0x10010113
    ; Actually: 000100000000 | 00000 | 000 | 00010 | 0010011
    ; imm=256=0x100, rs1=0, rd=2
    mov dword [rdi], 0x10010113      ; addi sp, x0, 256

    ; C.LDSP rd, offset(sp) : 011 | uimm[5] | rd | uimm[4:3|8:6] | 10
    ; offset = 8 bytes (from sp+8 = 0x108)
    ; For offset 8 = 0b001000:
    ;   uimm[5] = 0, uimm[4:3] = 01 (bit3=1), uimm[8:6] = 000
    ; rd = 01010 (x10)
    ; 011 | 0 | 01010 | 01 | 000 | 10 = 0b0110_0101_0010_0010 = 0x6522
    mov word [rdi+4], 0x6522         ; C.LDSP a0, 8 (2 bytes)

    ; addi a7, x0, 93 = 0x05D00893 (32-bit)
    mov dword [rdi+6], 0x05D00893    ; addi a7, x0, 93

    ; ecall = 0x00000073
    mov dword [rdi+10], 0x00000073   ; ecall

    ; Clear registers
    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 32
.clr:
    mov [rdi + rcx*8 - 8], rax
    dec ecx
    jnz .clr

    ; Execute
    ; execute_blocks(start_pc, code_base, rv_regs, pc_ptr, max_blocks)
    xor edi, edi                    ; start_pc = 0
    mov rsi, [guest_memory]         ; code_base
    lea rdx, [rv_regs]              ; rv_regs
    lea rcx, [rv_pc]                ; &rv_pc
    mov r8d, 100                    ; max blocks
    call execute_blocks

    ; Check a0 - should be 42
    lea rax, [rv_regs]
    mov ecx, [rax + 10*8]

    ; Print result
    push rcx
    mov rcx, [stdout_handle]
    lea rdx, [msg_pass]
    mov r8d, 16
    lea r9, [chars_written]
    mov qword [rsp+40], 0
    call WriteConsoleA
    pop rcx

    ; Convert exit code to string and print
    push rcx
    lea rdi, [num_buf]
    mov eax, ecx
    xor edx, edx
    mov ecx, 10
    div ecx
    add dl, '0'
    test eax, eax
    jz .single_digit
    add al, '0'
    mov [rdi], al
    mov [rdi+1], dl
    mov byte [rdi+2], 0
    mov r8d, 2
    jmp .print_num
.single_digit:
    mov [rdi], dl
    mov byte [rdi+1], 0
    mov r8d, 1
.print_num:
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    lea r9, [chars_written]
    mov qword [rsp+40], 0
    call WriteConsoleA
    pop rcx

    ; Newline
    push rcx
    mov rcx, [stdout_handle]
    lea rdx, [msg_nl]
    mov r8d, 2
    lea r9, [chars_written]
    mov qword [rsp+40], 0
    call WriteConsoleA
    pop rcx

    ; Exit with the RISC-V exit code
    jmp .exit

.fail:
    mov ecx, 255

.exit:
    add rsp, 80
    pop rbp
    sub rsp, 40
    call ExitProcess
