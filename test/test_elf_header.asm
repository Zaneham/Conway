; test_elf_header.asm - Verify ELF header is loaded correctly
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

PAGE_READWRITE          equ 0x04
MEM_COMMIT              equ 0x1000
MEM_RESERVE             equ 0x2000
GENERIC_READ            equ 0x80000000
FILE_SHARE_READ         equ 1
OPEN_EXISTING           equ 3
FILE_ATTRIBUTE_NORMAL   equ 0x80
STD_OUTPUT_HANDLE       equ -11

GUEST_MEM_SIZE          equ 134217728
ELF_BUFFER_SIZE         equ 8388608

section .data
    elf_path        db "doomgeneric/doomgeneric/doom_conway.elf", 0
    msg_ehdr        db "ELF header at 0x10000:", 13, 10, 0
    msg_magic       db "  Magic: ", 0
    msg_phentsize   db "  e_phentsize @0x36: ", 0
    msg_phnum       db "  e_phnum @0x38: ", 0
    msg_nl          db 13, 10, 0

section .bss
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

    ; Print header
    mov rcx, [stdout_handle]
    lea rdx, [msg_ehdr]
    mov r8d, 24
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Now check memory at 0x10000 (where ELF header should be)
    mov rdi, [guest_memory]

    ; Print magic
    mov rcx, [stdout_handle]
    lea rdx, [msg_magic]
    mov r8d, 9
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    mov eax, [rdi + 0x10000]      ; First 4 bytes (magic)
    lea rdi, [num_buf]
    call .print_hex
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 8
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    mov rcx, [stdout_handle]
    lea rdx, [msg_nl]
    mov r8d, 2
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print e_phentsize (at offset 0x36)
    mov rcx, [stdout_handle]
    lea rdx, [msg_phentsize]
    mov r8d, 21
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    mov rdi, [guest_memory]
    movzx eax, word [rdi + 0x10000 + 0x36]  ; e_phentsize at offset 0x36
    lea rdi, [num_buf]
    call .print_hex
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 8
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    mov rcx, [stdout_handle]
    lea rdx, [msg_nl]
    mov r8d, 2
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print e_phnum (at offset 0x38)
    mov rcx, [stdout_handle]
    lea rdx, [msg_phnum]
    mov r8d, 17
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    mov rdi, [guest_memory]
    movzx eax, word [rdi + 0x10000 + 0x38]  ; e_phnum at offset 0x38
    lea rdi, [num_buf]
    call .print_hex
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 8
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    mov rcx, [stdout_handle]
    lea rdx, [msg_nl]
    mov r8d, 2
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    mov ecx, 0
    jmp .exit

.exit:
    add rsp, 96
    pop rbp
    sub rsp, 40
    call ExitProcess

.print_hex:
    push rbx
    mov ebx, 8
.hex_loop:
    rol eax, 4
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
