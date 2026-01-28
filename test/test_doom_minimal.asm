; test_doom_minimal.asm - Minimal test to load Doom ELF
bits 64
default rel

extern load_elf
extern init_block_cache
extern code_buffer
extern ExitProcess
extern VirtualAlloc
extern VirtualProtect
extern CreateFileA
extern ReadFile
extern CloseHandle

PAGE_EXECUTE_READWRITE  equ 0x40
PAGE_READWRITE          equ 0x04
MEM_COMMIT              equ 0x1000
MEM_RESERVE             equ 0x2000
GENERIC_READ            equ 0x80000000
FILE_SHARE_READ         equ 1
OPEN_EXISTING           equ 3
FILE_ATTRIBUTE_NORMAL   equ 0x80
INVALID_HANDLE_VALUE    equ -1

GUEST_MEM_SIZE          equ 8388608
CODE_BUFFER_SIZE        equ 16777216
ELF_BUFFER_SIZE         equ 8388608

section .data
    elf_path        db "doomgeneric/doomgeneric/doom_conway.elf", 0

section .bss
    old_protect     resd 1
    alignb 8
    file_handle     resq 1
    bytes_read      resq 1
    elf_buffer      resq 1
    guest_memory    resq 1

section .text
    global main

main:
    push rbp
    mov rbp, rsp
    sub rsp, 80

    ; Checkpoint 1
    mov ecx, 1
    ; jmp .exit

    ; Allocate ELF buffer
    xor ecx, ecx
    mov edx, ELF_BUFFER_SIZE
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz .fail
    mov [elf_buffer], rax

    ; Checkpoint 2
    mov ecx, 2
    ; jmp .exit

    ; Allocate guest memory
    xor ecx, ecx
    mov edx, GUEST_MEM_SIZE
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz .fail
    mov [guest_memory], rax

    ; Checkpoint 3
    mov ecx, 3
    ; jmp .exit

    ; Make code buffer executable
    lea rcx, [code_buffer]
    mov edx, CODE_BUFFER_SIZE
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    ; Checkpoint 4
    mov ecx, 4
    ; jmp .exit

    call init_block_cache

    ; Checkpoint 5
    mov ecx, 5
    ; jmp .exit

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
    je .fail
    mov [file_handle], rax

    ; Checkpoint 6
    mov ecx, 6
    ; jmp .exit

    ; Read file
    mov rcx, [file_handle]
    mov rdx, [elf_buffer]
    mov r8d, ELF_BUFFER_SIZE
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call ReadFile
    test eax, eax
    jz .fail

    ; Checkpoint 7
    mov ecx, 7
    ; jmp .exit

    mov rcx, [file_handle]
    call CloseHandle

    ; Load ELF
    mov rdi, [elf_buffer]
    mov rsi, [bytes_read]
    mov rdx, [guest_memory]
    mov rcx, GUEST_MEM_SIZE
    call load_elf
    test eax, eax
    jnz .fail

    ; Success - exit 42
    mov ecx, 42
    jmp .exit

.fail:
    mov ecx, 255

.exit:
    add rsp, 80
    pop rbp
    sub rsp, 40
    call ExitProcess
