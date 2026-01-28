; entry_test.asm - Minimal test to check entry point
bits 64
default rel

extern load_elf
extern get_elf_entry_point
extern ExitProcess
extern CreateFileA
extern ReadFile
extern CloseHandle
extern GetCommandLineA

GENERIC_READ            equ 0x80000000
FILE_SHARE_READ         equ 1
OPEN_EXISTING           equ 3
FILE_ATTRIBUTE_NORMAL   equ 0x80
INVALID_HANDLE_VALUE    equ -1

section .bss
    file_handle     resq 1
    bytes_read      resq 1
    elf_buffer      resb 131072     ; 128KB
    guest_memory    resb 131072     ; 128KB
    elf_path        resq 1

section .text
    global main

quick_exit:
    sub rsp, 40
    call ExitProcess

main:
    push rbp
    mov rbp, rsp
    sub rsp, 96                     ; Align to 16 bytes + shadow space

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
    jmp .open_file
.no_arg:
    mov ecx, 99
    jmp quick_exit

.open_file:
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

    mov rcx, [file_handle]
    lea rdx, [elf_buffer]
    mov r8d, 131072
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call ReadFile

    mov rcx, [file_handle]
    call CloseHandle

    ; Load ELF
    lea rdi, [elf_buffer]
    mov rsi, [bytes_read]
    lea rdx, [guest_memory]
    mov rcx, 131072
    call load_elf
    test eax, eax
    jnz .load_error

    ; Get entry point and exit with low byte as code
    call get_elf_entry_point
    shr eax, 4              ; Divide by 16 to fit in byte
    mov ecx, eax
    jmp quick_exit

.file_error:
    mov ecx, 200
    jmp quick_exit

.load_error:
    mov ecx, 201
    jmp quick_exit
