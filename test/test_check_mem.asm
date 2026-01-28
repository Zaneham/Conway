; test_check_mem.asm - Verify memory at stack locations
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

GUEST_MEM_SIZE          equ 134217728
CODE_BUFFER_SIZE        equ 16777216
ELF_BUFFER_SIZE         equ 8388608

section .data
    elf_path        db "doomgeneric/doomgeneric/doom_conway.elf", 0
    msg_addr        db "Addr ", 0
    msg_val         db ": ", 0
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

    ; Check memory at 0x700018 BEFORE we set it up
    mov rdi, [guest_memory]
    mov rax, [rdi + 0x700018]
    lea rdi, [num_buf]
    mov qword [rdi], 'BEF:    '   ; "BEF:" marker
    add rdi, 4
    call .print_hex64
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 20
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    mov rcx, [stdout_handle]
    lea rdx, [msg_nl]
    mov r8d, 2
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Set up stack with the same values as test_doom_limited
    mov rdi, [guest_memory]

    ; "doom" string at 0x6FE000
    mov byte [rdi + 0x6FE000], 'd'
    mov byte [rdi + 0x6FE001], 'o'
    mov byte [rdi + 0x6FE002], 'o'
    mov byte [rdi + 0x6FE003], 'm'
    mov byte [rdi + 0x6FE004], 0

    ; Stack data at 0x700000
    mov qword [rdi + 0x700000], 1           ; argc = 1
    mov qword [rdi + 0x700008], 0x6FE000    ; argv[0] = "doom"
    mov qword [rdi + 0x700010], 0           ; argv[1] = NULL
    mov qword [rdi + 0x700018], 0           ; envp[0] = NULL
    mov qword [rdi + 0x700020], 0           ; auxv[0] = AT_NULL
    mov qword [rdi + 0x700028], 0           ; auxv value

    ; Now dump what's at these addresses
    mov r15, 0x700000

.dump_loop:
    ; Print address
    mov rcx, [stdout_handle]
    lea rdx, [msg_addr]
    mov r8d, 5
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    mov eax, r15d
    lea rdi, [num_buf]
    call .print_hex
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 8
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print ": "
    mov rcx, [stdout_handle]
    lea rdx, [msg_val]
    mov r8d, 2
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print value (8 bytes)
    mov rdi, [guest_memory]
    mov rax, [rdi + r15]
    lea rdi, [num_buf]
    call .print_hex64
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 16
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Newline
    mov rcx, [stdout_handle]
    lea rdx, [msg_nl]
    mov r8d, 2
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    add r15, 8
    cmp r15, 0x700040
    jl .dump_loop

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

.print_hex64:
    push rbx
    mov ebx, 16
.hex64_loop:
    rol rax, 4
    mov ecx, eax
    and ecx, 0xF
    cmp cl, 10
    jb .hex64_digit
    add cl, 'A'-10
    jmp .hex64_store
.hex64_digit:
    add cl, '0'
.hex64_store:
    mov [rdi], cl
    inc rdi
    dec ebx
    jnz .hex64_loop
    pop rbx
    ret
