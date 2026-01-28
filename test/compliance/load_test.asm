; load_test.asm - Test ELF loading
bits 64
default rel

extern ExitProcess
extern GetCommandLineA
extern CreateFileA
extern ReadFile
extern CloseHandle
extern load_elf
extern get_elf_entry_point

GENERIC_READ            equ 0x80000000
FILE_SHARE_READ         equ 1
OPEN_EXISTING           equ 3
FILE_ATTRIBUTE_NORMAL   equ 0x80
INVALID_HANDLE_VALUE    equ -1

section .bss
    alignb 8
    file_handle     resq 1
    bytes_read      resq 1
    elf_buffer      resb 131072     ; 128KB
    guest_memory    resb 131072     ; 128KB
    elf_path        resq 1

section .text
    global main

main:
    push rbp
    mov rbp, rsp
    sub rsp, 96

    ; Exit code 10 = checkpoint 1
    mov dword [rbp-4], 10

    ; Get command line
    call GetCommandLineA
    test rax, rax
    jz .exit
    mov rsi, rax

    ; Checkpoint 2
    mov dword [rbp-4], 20

    ; Skip past executable name
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

    ; Checkpoint 3
    mov dword [rbp-4], 30

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

    ; Checkpoint 4
    mov dword [rbp-4], 40

    ; Read file
    mov rcx, [file_handle]
    lea rdx, [elf_buffer]
    mov r8d, 131072
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call ReadFile
    test eax, eax
    jz .read_error

    ; Checkpoint 5
    mov dword [rbp-4], 50

    mov rcx, [file_handle]
    call CloseHandle

    ; Checkpoint 6
    mov dword [rbp-4], 60

    ; Load ELF
    lea rdi, [elf_buffer]
    mov rsi, [bytes_read]
    lea rdx, [guest_memory]
    mov rcx, 131072
    call load_elf
    test eax, eax
    jnz .load_error

    ; Checkpoint 7
    mov dword [rbp-4], 70

    ; Get entry point
    call get_elf_entry_point
    shr eax, 4
    mov dword [rbp-4], eax      ; Entry point / 16 as exit code

    jmp .exit

.no_arg:
    mov dword [rbp-4], 99
    jmp .exit

.file_error:
    mov dword [rbp-4], 100
    jmp .exit

.read_error:
    mov dword [rbp-4], 101
    jmp .exit

.load_error:
    mov dword [rbp-4], 102
    jmp .exit

.exit:
    mov ecx, [rbp-4]
    add rsp, 96
    pop rbp
    sub rsp, 40
    call ExitProcess
