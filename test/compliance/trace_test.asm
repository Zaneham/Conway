; trace_test.asm - Run with limited blocks to see progress
bits 64
default rel

extern load_elf
extern get_elf_entry_point
extern init_block_cache
extern execute_blocks
extern code_buffer
extern ExitProcess
extern VirtualProtect
extern CreateFileA
extern ReadFile
extern CloseHandle
extern GetCommandLineA

PAGE_EXECUTE_READWRITE  equ 0x40
GENERIC_READ            equ 0x80000000
FILE_SHARE_READ         equ 1
OPEN_EXISTING           equ 3
FILE_ATTRIBUTE_NORMAL   equ 0x80
INVALID_HANDLE_VALUE    equ -1

section .bss
    old_protect     resd 1
    alignb 8
    file_handle     resq 1
    bytes_read      resq 1
    elf_buffer      resb 2097152
    guest_memory    resb 2097152
    rv_regs         resq 32
    rv_fp_regs      resq 32
    rv_pc           resq 1
    elf_path        resq 1

section .text
    global main

quick_exit:
    sub rsp, 40
    call ExitProcess

main:
    push rbp
    mov rbp, rsp
    sub rsp, 96

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
    call quick_exit

.start_exec:
    lea rcx, [code_buffer]
    mov rdx, 1048576
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    call init_block_cache

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
    mov r8d, 2097152
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call ReadFile

    mov rcx, [file_handle]
    call CloseHandle

    lea rdi, [elf_buffer]
    mov rsi, [bytes_read]
    lea rdx, [guest_memory]
    mov rcx, 2097152
    call load_elf
    test eax, eax
    jnz .load_error

    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 32
.clr:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .clr

    ; Clear FP regs
    lea rdi, [rv_fp_regs]
    mov ecx, 32
.clr_fp:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .clr_fp

    ; Execute blocks
    call get_elf_entry_point
    mov edi, eax
    lea rsi, [guest_memory]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    xor r8d, r8d                ; Unlimited blocks
    lea r9, [rv_fp_regs]        ; FP registers
    call execute_blocks

    ; Return a0 as exit code (same as conway_test)
    mov ecx, [rv_regs + 10*8]
    call quick_exit

.file_error:
    mov ecx, 200
    call quick_exit

.load_error:
    mov ecx, 201
    call quick_exit
