; test_decode_loop.asm - Decode instructions at the loop by reading bytes properly
bits 64
default rel

extern load_elf
extern elf_entry_point
extern init_block_cache
extern code_buffer
extern ExitProcess
extern VirtualAlloc
extern VirtualProtect
extern CreateFileA
extern ReadFile
extern CloseHandle
extern GetStdHandle
extern WriteFile

PAGE_EXECUTE_READWRITE  equ 0x40
PAGE_READWRITE          equ 0x04
MEM_COMMIT              equ 0x1000
MEM_RESERVE             equ 0x2000
GENERIC_READ            equ 0x80000000
FILE_SHARE_READ         equ 1
OPEN_EXISTING           equ 3
FILE_ATTRIBUTE_NORMAL   equ 0x80
STD_OUTPUT_HANDLE       equ -11

GUEST_MEM_SIZE          equ 8388608
CODE_BUFFER_SIZE        equ 16777216
ELF_BUFFER_SIZE         equ 8388608

section .data
    elf_path        db "doomgeneric/doomgeneric/doom_conway.elf", 0
    msg_at          db "0x", 0
    msg_colon       db ": ", 0
    msg_nl          db 13, 10, 0

section .bss
    old_protect     resd 1
    alignb 8
    file_handle     resq 1
    bytes_read      resq 1
    stdout_handle   resq 1
    chars_written   resq 1
    elf_buffer      resq 1
    guest_memory    resq 1
    num_buf         resb 32

section .text
    global main

main:
    push rbp
    mov rbp, rsp
    sub rsp, 96
    push r12
    push r13
    push r14
    push r15

    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [stdout_handle], rax

    xor ecx, ecx
    mov edx, ELF_BUFFER_SIZE
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_READWRITE
    call VirtualAlloc
    mov [elf_buffer], rax

    xor ecx, ecx
    mov edx, GUEST_MEM_SIZE
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_READWRITE
    call VirtualAlloc
    mov [guest_memory], rax

    lea rcx, [code_buffer]
    mov edx, CODE_BUFFER_SIZE
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    call init_block_cache

    lea rcx, [elf_path]
    mov rdx, GENERIC_READ
    mov r8d, FILE_SHARE_READ
    xor r9d, r9d
    mov qword [rsp+32], OPEN_EXISTING
    mov qword [rsp+40], FILE_ATTRIBUTE_NORMAL
    mov qword [rsp+48], 0
    call CreateFileA
    mov [file_handle], rax

    mov rcx, [file_handle]
    mov rdx, [elf_buffer]
    mov r8d, ELF_BUFFER_SIZE
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call ReadFile

    mov rcx, [file_handle]
    call CloseHandle

    mov rdi, [elf_buffer]
    mov rsi, [bytes_read]
    mov rdx, [guest_memory]
    mov rcx, GUEST_MEM_SIZE
    call load_elf

    ; Dump bytes from 0x67E20 to 0x67E80 as individual bytes with PC
    mov r12, [guest_memory]
    mov r13, 0x67E20         ; start PC

.dump_loop:
    ; Print "0x"
    mov rcx, [stdout_handle]
    lea rdx, [msg_at]
    mov r8d, 2
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print PC (5 hex digits)
    mov eax, r13d
    lea rdi, [num_buf]
    call .print_hex5
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 5
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print ": "
    mov rcx, [stdout_handle]
    lea rdx, [msg_colon]
    mov r8d, 2
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Read 2 bytes at PC (could be compressed instr)
    movzx eax, word [r12 + r13]
    lea rdi, [num_buf]
    call .print_hex4
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 4
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Check if it's a 32-bit instruction (bits[1:0] == 11)
    movzx eax, word [r12 + r13]
    and eax, 3
    cmp eax, 3
    jne .is_16bit

    ; It's 32-bit, print next 2 bytes
    movzx eax, word [r12 + r13 + 2]
    lea rdi, [num_buf]
    call .print_hex4
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 4
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    add r13, 4
    jmp .print_newline

.is_16bit:
    add r13, 2

.print_newline:
    mov rcx, [stdout_handle]
    lea rdx, [msg_nl]
    mov r8d, 2
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    cmp r13, 0x67E80
    jl .dump_loop

    mov ecx, 0
    jmp .exit

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    add rsp, 96
    pop rbp
    sub rsp, 40
    call ExitProcess

; Print 5-digit hex (20 bits) in EAX to [RDI]
.print_hex5:
    push rbx
    mov ebx, 5
    shl eax, 12         ; Shift to align for rotation
.hex5_loop:
    rol eax, 4
    mov ecx, eax
    and ecx, 0xF
    cmp cl, 10
    jb .hex5_digit
    add cl, 'A'-10
    jmp .hex5_store
.hex5_digit:
    add cl, '0'
.hex5_store:
    mov [rdi], cl
    inc rdi
    dec ebx
    jnz .hex5_loop
    pop rbx
    ret

; Print 4-digit hex (16 bits) in AX to [RDI]
.print_hex4:
    push rbx
    mov ebx, 4
    shl eax, 16
.hex4_loop:
    rol eax, 4
    mov ecx, eax
    and ecx, 0xF
    cmp cl, 10
    jb .hex4_digit
    add cl, 'A'-10
    jmp .hex4_store
.hex4_digit:
    add cl, '0'
.hex4_store:
    mov [rdi], cl
    inc rdi
    dec ebx
    jnz .hex4_loop
    pop rbx
    ret
