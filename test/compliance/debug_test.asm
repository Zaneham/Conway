; debug_test.asm - Print ELF entry point
bits 64
default rel

extern load_elf
extern get_elf_entry_point
extern ExitProcess
extern VirtualProtect
extern CreateFileA
extern ReadFile
extern CloseHandle
extern GetCommandLineA
extern GetStdHandle
extern WriteFile
extern code_buffer
extern init_block_cache

PAGE_EXECUTE_READWRITE  equ 0x40
GENERIC_READ            equ 0x80000000
FILE_SHARE_READ         equ 1
OPEN_EXISTING           equ 3
FILE_ATTRIBUTE_NORMAL   equ 0x80
INVALID_HANDLE_VALUE    equ -1
STD_OUTPUT_HANDLE       equ -11

section .data
    hex_chars       db "0123456789ABCDEF"
    msg_entry       db "Entry: 0x", 0
    msg_loaded      db "Loaded OK", 13, 10, 0
    msg_fail        db "Load FAIL", 13, 10, 0
    newline         db 13, 10, 0

section .bss
    old_protect     resd 1
    alignb 8
    my_stdout       resq 1
    file_handle     resq 1
    bytes_read      resq 1
    my_written      resq 1
    elf_buffer      resb 2097152
    guest_memory    resb 2097152
    hex_buf         resb 20
    elf_path        resq 1

section .text
    global main

quick_exit:
    sub rsp, 40
    call ExitProcess

print_string:
    ; RCX = string ptr
    push rcx
    mov rdi, rcx
    xor eax, eax
    mov ecx, 256
    repne scasb
    sub rdi, 1
    pop rdx
    sub rdi, rdx
    mov r8, rdi
    mov rcx, [my_stdout]
    lea r9, [my_written]
    mov qword [rsp+32], 0
    call WriteFile
    ret

print_hex64:
    ; RAX = value to print
    push rbx
    push rdi
    lea rdi, [hex_buf]
    mov rcx, 16
.hex_loop:
    rol rax, 4
    mov rbx, rax
    and rbx, 0xF
    mov bl, [hex_chars + rbx]
    mov [rdi], bl
    inc rdi
    dec rcx
    jnz .hex_loop
    mov byte [rdi], 0
    lea rcx, [hex_buf]
    call print_string
    pop rdi
    pop rbx
    ret

main:
    push rbp
    mov rbp, rsp
    sub rsp, 96

    ; Get stdout
    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [my_stdout], rax

    ; Get command line
    call GetCommandLineA
    mov rsi, rax
.skip_exe:
    lodsb
    test al, al
    jz .no_arg
    cmp al, ' '
    jne .skip_exe
.skip_spaces:
    lodsb
    cmp al, ' '
    je .skip_spaces
    test al, al
    jz .no_arg
    dec rsi
    mov [elf_path], rsi
    jmp .start_exec
.no_arg:
    mov ecx, 99
    jmp quick_exit

.start_exec:
    ; VirtualProtect
    lea rcx, [code_buffer]
    mov rdx, 1048576
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    call init_block_cache

    ; Open file
    mov rcx, [elf_path]
    mov rdx, GENERIC_READ
    mov r8d, FILE_SHARE_READ
    xor r9d, r9d
    mov qword [rsp+32], OPEN_EXISTING
    mov qword [rsp+40], FILE_ATTRIBUTE_NORMAL
    mov qword [rsp+48], 0
    call CreateFileA
    cmp rax, INVALID_HANDLE_VALUE
    je .file_error
    mov [file_handle], rax

    ; Read file
    mov rcx, [file_handle]
    lea rdx, [elf_buffer]
    mov r8d, 2097152
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call ReadFile

    mov rcx, [file_handle]
    call CloseHandle

    ; Load ELF
    lea rdi, [elf_buffer]
    mov rsi, [bytes_read]
    lea rdx, [guest_memory]
    mov rcx, 2097152
    call load_elf
    test eax, eax
    jnz .load_fail

    ; Get entry point and exit with it as code
    call get_elf_entry_point
    mov ecx, eax                ; Entry point as exit code
    jmp quick_exit

.file_error:
    mov ecx, 100
    jmp quick_exit

.load_fail:
    lea rcx, [msg_fail]
    call print_string
    mov ecx, 101
    jmp quick_exit
