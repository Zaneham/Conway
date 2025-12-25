; conway_test.asm - Conway compliance test runner
; Accepts an ELF file path as command line argument
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
    default_path    db "test/riscv/fib.elf", 0
    err_usage       db "Usage: conway_test <elf_file>", 13, 10, 0
    err_file        db "Error: Could not open file", 13, 10, 0

section .bss
    old_protect     resd 1
    alignb 8
    file_handle     resq 1
    bytes_read      resq 1
    elf_buffer      resb 65536
    guest_memory    resb 65536
    rv_regs         resq 32
    rv_pc           resq 1
    elf_path        resq 1          ; Pointer to ELF path

section .text
    global main

; Exit with code in ECX
quick_exit:
    sub rsp, 40
    call ExitProcess

main:
    push rbp
    mov rbp, rsp
    sub rsp, 80

    ; Save argc and argv
    ; Windows x64: rcx = argc, rdx = argv
    mov [rbp-8], rcx            ; argc
    mov [rbp-16], rdx           ; argv

    ; Check argc - need at least 2 (program name + elf path)
    cmp rcx, 2
    jl .use_default

    ; Get argv[1] (the ELF path)
    mov rax, [rbp-16]           ; argv
    mov rax, [rax+8]            ; argv[1]
    mov [elf_path], rax
    jmp .start_execution

.use_default:
    lea rax, [default_path]
    mov [elf_path], rax

.start_execution:
    ; VirtualProtect on code buffer
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
    mov rcx, rax                ; file handle
    lea rdx, [elf_buffer]
    mov r8d, 65536
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call ReadFile

    ; Close file
    mov rcx, [file_handle]
    call CloseHandle

    ; Load ELF
    lea rcx, [elf_buffer]
    mov rdx, [bytes_read]
    lea r8, [guest_memory]
    call load_elf
    test rax, rax
    jz .load_error

    ; Get entry point
    call elf_entry_point
    mov [rv_pc], rax

    ; Clear registers
    lea rdi, [rv_regs]
    xor rax, rax
    mov rcx, 32
    rep stosq

    ; Set up stack pointer (x2 = sp)
    lea rax, [guest_memory + 65536 - 256]
    mov [rv_regs + 2*8], rax

    ; Execute
    lea rcx, [rv_regs]
    lea rdx, [rv_pc]
    lea r8, [guest_memory]
    call execute_blocks

    ; Get exit code from a0 (x10)
    mov ecx, [rv_regs + 10*8]
    call quick_exit

.file_error:
    mov ecx, 100
    call quick_exit

.load_error:
    mov ecx, 101
    call quick_exit
