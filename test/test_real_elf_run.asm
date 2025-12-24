; test_real_elf_run.asm - Load and execute a real RISC-V ELF binary
; "It works! It actually works!" - Every developer, eventually
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
    elf_path        db "test/riscv/fib.elf", 0

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

; Quick exit helper
quick_exit:
    ; ECX already has exit code
    sub rsp, 40
    call ExitProcess

main:
    push rbp
    mov rbp, rsp
    sub rsp, 80

    ; === CHECKPOINT 1 ===
    mov ecx, 1
    ; call quick_exit        ; Uncomment to test

    ; VirtualProtect
    lea rcx, [code_buffer]
    mov rdx, 1048576
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    ; === CHECKPOINT 2 ===
    mov ecx, 2
    ; call quick_exit

    call init_block_cache

    ; === CHECKPOINT 3 ===
    mov ecx, 3
    ; call quick_exit

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

    ; === CHECKPOINT 4 ===
    mov ecx, 4
    ; call quick_exit

    ; Read file
    mov rcx, [file_handle]
    lea rdx, [elf_buffer]
    mov r8d, 65536
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call ReadFile

    test eax, eax
    jz .fail_101

    ; === CHECKPOINT 5 ===
    mov ecx, 5
    ; call quick_exit

    mov rcx, [file_handle]
    call CloseHandle

    ; === CHECKPOINT 6 ===
    mov ecx, 6
    ; call quick_exit

    ; Load ELF (skip clearing memory for now)
    lea rdi, [elf_buffer]
    mov rsi, [bytes_read]
    lea rdx, [guest_memory]
    mov rcx, 65536
    call load_elf

    test eax, eax
    jnz .fail_load

    ; === CHECKPOINT 7 ===
    mov ecx, 7
    ; call quick_exit

    ; Clear regs
    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 32
.clr:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .clr

    ; === CHECKPOINT 8 ===
    mov ecx, 8
    ; call quick_exit

    ; Execute
    xor edi, edi
    lea rsi, [guest_memory]
    add rsi, 0x1000
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8d, 1000                   ; Enough blocks for larger benchmarks
    call execute_blocks

    ; === CHECKPOINT 9 ===
    ; Get result
    lea rax, [rv_regs]
    mov ecx, [rax + 80]             ; a0 = x10, offset = 10*8 = 80
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
