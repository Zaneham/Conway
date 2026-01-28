; test_regs.asm - Dump all registers before crash
bits 64
default rel

extern load_elf
extern elf_entry_point
extern init_block_cache
extern execute_blocks
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
INVALID_HANDLE_VALUE    equ -1
STD_OUTPUT_HANDLE       equ -11

GUEST_MEM_SIZE          equ 8388608
CODE_BUFFER_SIZE        equ 16777216
ELF_BUFFER_SIZE         equ 8388608

section .data
    elf_path        db "doomgeneric/doomgeneric/doom_conway.elf", 0
    msg_regs        db "Registers before block 262166:", 13, 10, 0
    msg_x           db "x", 0
    msg_eq          db "=", 0
    msg_sp          db " ", 0
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
    rv_regs         resq 32
    rv_pc           resq 1
    num_buf         resb 32
    reg_idx         resq 1

section .text
    global main

main:
    push rbp
    mov rbp, rsp
    sub rsp, 96

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

    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 32
.clr:
    mov [rdi + rcx*8 - 8], rax
    dec ecx
    jnz .clr

    lea rax, [rv_regs]
    mov qword [rax + 2*8], 0x700000
    mov qword [rax + 10*8], 1
    mov qword [rax + 11*8], 0x6FF000

    mov rdi, [guest_memory]
    mov byte [rdi + 0x6FE000], 'd'
    mov byte [rdi + 0x6FE001], 'o'
    mov byte [rdi + 0x6FE002], 'o'
    mov byte [rdi + 0x6FE003], 'm'
    mov byte [rdi + 0x6FE004], 0
    mov qword [rdi + 0x6FF000], 0x6FE000
    mov qword [rdi + 0x6FF008], 0
    mov qword [rdi + 0xF000], 0x200000

    ; Run 262165 blocks
    mov rdi, [elf_entry_point]
    mov rsi, [guest_memory]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8d, 262165
    call execute_blocks

    ; Print header
    mov rcx, [stdout_handle]
    lea rdx, [msg_regs]
    mov r8d, 32
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print all 32 registers
    mov qword [reg_idx], 0
.print_loop:
    ; Print "x"
    mov rcx, [stdout_handle]
    lea rdx, [msg_x]
    mov r8d, 1
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print reg number
    mov eax, [reg_idx]
    lea rdi, [num_buf]
    call .print_dec
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 2
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print "="
    mov rcx, [stdout_handle]
    lea rdx, [msg_eq]
    mov r8d, 1
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print reg value
    mov rax, [reg_idx]
    lea rcx, [rv_regs]
    mov rax, [rcx + rax*8]
    lea rdi, [num_buf]
    call .print_hex64
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 16
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print space or newline
    mov rax, [reg_idx]
    and eax, 3
    cmp eax, 3
    je .print_nl
    mov rcx, [stdout_handle]
    lea rdx, [msg_sp]
    mov r8d, 1
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile
    jmp .next_reg
.print_nl:
    mov rcx, [stdout_handle]
    lea rdx, [msg_nl]
    mov r8d, 2
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile
.next_reg:
    inc qword [reg_idx]
    cmp qword [reg_idx], 32
    jl .print_loop

    ; Print PC
    mov rcx, [stdout_handle]
    lea rdx, [msg_x]
    mov r8d, 1
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    mov rax, [rv_pc]
    lea rdi, [num_buf]
    call .print_hex64
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 16
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    mov rcx, [stdout_handle]
    lea rdx, [msg_nl]
    mov r8d, 2
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Now try running block 262166
    mov rdi, [rv_pc]            ; Continue from where we left off
    mov rsi, [guest_memory]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8d, 1
    call execute_blocks

    mov ecx, 0
    jmp .exit

.exit:
    add rsp, 96
    pop rbp
    sub rsp, 40
    call ExitProcess

; Print 2-digit decimal
.print_dec:
    xor edx, edx
    mov ecx, 10
    div ecx
    add al, '0'
    mov [rdi], al
    add dl, '0'
    mov [rdi+1], dl
    ret

; Print 64-bit hex
.print_hex64:
    push rbx
    mov rbx, 16
.hex_loop:
    rol rax, 4
    mov ecx, eax
    and ecx, 0xF
    cmp cl, 10
    jb .hex_digit
    add cl, 'A'-10
    jmp .hex_store
.hex_digit:
    add cl, '0'
.hex_store:
    mov [rdi], cl
    inc rdi
    dec ebx
    jnz .hex_loop
    pop rbx
    ret
