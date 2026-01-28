; test_syscalls.asm - Test Linux syscall implementations
; "Making sure the teapot can actually pour"
bits 64
default rel

extern load_elf
extern elf_entry_point
extern init_block_cache
extern execute_blocks
extern code_buffer
extern ExitProcess
extern VirtualProtect
extern CreateFileA
extern ReadFile
extern CloseHandle

PAGE_EXECUTE_READWRITE  equ 0x40
GENERIC_READ            equ 0x80000000
FILE_SHARE_READ         equ 1
OPEN_EXISTING           equ 3
FILE_ATTRIBUTE_NORMAL   equ 0x80
INVALID_HANDLE_VALUE    equ -1

section .data
    elf_path        db "test/riscv/syscall_test.elf", 0

section .bss
    old_protect     resd 1
    alignb 8
    file_handle     resq 1
    bytes_read      resq 1
    elf_buffer      resb 65536
    guest_memory    resb 65536
    rv_regs         resq 32
    rv_pc           resq 1

section .text
    global main

quick_exit:
    sub rsp, 40
    call ExitProcess

main:
    push rbp
    mov rbp, rsp
    sub rsp, 80

    ; VirtualProtect
    lea rcx, [code_buffer]
    mov rdx, 1048576
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    call init_block_cache

    ; Open file
    lea rcx, [elf_path]
    mov rdx, GENERIC_READ
    mov r8d, FILE_SHARE_READ
    xor r9d, r9d
    mov qword [rsp+32], OPEN_EXISTING
    mov qword [rsp+40], FILE_ATTRIBUTE_NORMAL
    mov qword [rsp+48], 0
    call CreateFileA

    cmp rax, INVALID_HANDLE_VALUE
    je .fail_100
    mov [file_handle], rax

    ; Read file
    mov rcx, [file_handle]
    lea rdx, [elf_buffer]
    mov r8d, 65536
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call ReadFile

    test eax, eax
    jz .fail_101

    mov rcx, [file_handle]
    call CloseHandle

    ; Load ELF
    lea rdi, [elf_buffer]
    mov rsi, [bytes_read]
    lea rdx, [guest_memory]
    mov rcx, 65536
    call load_elf

    test eax, eax
    jnz .fail_load

    ; Clear regs
    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 32
.clr:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .clr

    ; Execute
    xor edi, edi
    lea rsi, [guest_memory]
    add rsi, 0x1000
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8d, 1000
    call execute_blocks

    ; Get result
    lea rax, [rv_regs]
    mov ecx, [rax + 80]             ; a0 = x10
    call quick_exit

.fail_100:
    mov ecx, 100
    call quick_exit

.fail_101:
    mov ecx, 101
    call quick_exit

.fail_load:
    add eax, 110
    mov ecx, eax
    call quick_exit
