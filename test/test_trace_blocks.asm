; test_trace_blocks.asm - Run blocks one at a time with debug output
bits 64
default rel

extern load_elf
extern elf_entry_point
extern init_block_cache
extern execute_blocks
extern code_buffer
extern debug_block_count
extern debug_last_pc
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
    msg_block       db "B", 0
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
    rv_regs         resq 32
    rv_pc           resq 1
    num_buf         resb 32
    block_num       resq 1

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

    ; Clear registers
    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 32
.clr:
    mov [rdi + rcx*8 - 8], rax
    dec ecx
    jnz .clr

    ; Stack setup with envp NULL-terminated
    mov rdi, [guest_memory]
    mov byte [rdi + 0x6FE000], 'd'
    mov byte [rdi + 0x6FE001], 'o'
    mov byte [rdi + 0x6FE002], 'o'
    mov byte [rdi + 0x6FE003], 'm'
    mov byte [rdi + 0x6FE004], 0

    mov qword [rdi + 0x700000], 1
    mov qword [rdi + 0x700008], 0x6FE000
    mov qword [rdi + 0x700010], 0
    mov qword [rdi + 0x700018], 0
    mov qword [rdi + 0x700020], 0
    mov qword [rdi + 0x700028], 0

    lea rax, [rv_regs]
    mov qword [rax + 2*8], 0x700000
    mov qword [rax + 10*8], 1
    mov qword [rax + 11*8], 0x700008
    mov qword [rdi + 0xF000], 0x200000

    ; Initialize PC for first run
    mov rax, [elf_entry_point]
    mov [rv_pc], rax

    mov qword [block_num], 0

.run_loop:
    ; Print "B" before each block
    mov rcx, [stdout_handle]
    lea rdx, [msg_block]
    mov r8d, 1
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Run 1 block
    mov rdi, [rv_pc]
    mov rsi, [guest_memory]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8d, 1
    call execute_blocks

    inc qword [block_num]
    cmp qword [block_num], 500000
    jl .run_loop

    ; Newline
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
