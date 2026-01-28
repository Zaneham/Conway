; test_trace.asm - Trace PC changes around block 262165
bits 64
default rel

extern load_elf
extern elf_entry_point
extern init_block_cache
extern execute_blocks
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
INVALID_HANDLE_VALUE    equ -1
STD_OUTPUT_HANDLE       equ -11

GUEST_MEM_SIZE          equ 8388608
CODE_BUFFER_SIZE        equ 16777216
ELF_BUFFER_SIZE         equ 8388608

section .data
    elf_path        db "doomgeneric/doomgeneric/doom_conway.elf", 0
    msg_loading     db "Loading...", 13, 10, 0
    msg_block       db "Blk ", 0
    msg_pc          db " PC: ", 0
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
    block_count     resq 1

section .text
    global main

main:
    push rbp
    mov rbp, rsp
    sub rsp, 96

    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [stdout_handle], rax

    mov rcx, rax
    lea rdx, [msg_loading]
    mov r8d, 12
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    xor ecx, ecx
    mov edx, ELF_BUFFER_SIZE
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz .fail
    mov [elf_buffer], rax

    xor ecx, ecx
    mov edx, GUEST_MEM_SIZE
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz .fail
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
    cmp rax, INVALID_HANDLE_VALUE
    je .fail
    mov [file_handle], rax

    mov rcx, [file_handle]
    mov rdx, [elf_buffer]
    mov r8d, ELF_BUFFER_SIZE
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call ReadFile
    test eax, eax
    jz .fail

    mov rcx, [file_handle]
    call CloseHandle

    mov rdi, [elf_buffer]
    mov rsi, [bytes_read]
    mov rdx, [guest_memory]
    mov rcx, GUEST_MEM_SIZE
    call load_elf
    test eax, eax
    jnz .fail

    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 32
.clr_regs:
    mov [rdi + rcx*8 - 8], rax
    dec ecx
    jnz .clr_regs

    lea rax, [rv_regs]
    mov qword [rax + 2*8], 0x700000

    mov rdi, [guest_memory]
    mov byte [rdi + 0x6FE000], 'd'
    mov byte [rdi + 0x6FE001], 'o'
    mov byte [rdi + 0x6FE002], 'o'
    mov byte [rdi + 0x6FE003], 'm'
    mov byte [rdi + 0x6FE004], 0
    mov qword [rdi + 0x6FF000], 0x6FE000
    mov qword [rdi + 0x6FF008], 0

    lea rax, [rv_regs]
    mov qword [rax + 10*8], 1
    mov qword [rax + 11*8], 0x6FF000
    mov qword [rdi + 0xF000], 0x200000

    ; First run 262160 blocks to get close
    mov rdi, [elf_entry_point]
    mov rsi, [guest_memory]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8d, 262160
    call execute_blocks
    mov qword [block_count], 262160

    ; Now run one block at a time and print PC
.trace_loop:
    ; Print "Blk "
    mov rcx, [stdout_handle]
    lea rdx, [msg_block]
    mov r8d, 4
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print block number
    mov eax, [block_count]
    lea rdi, [num_buf]
    call .print_hex
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 8
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print " PC: "
    mov rcx, [stdout_handle]
    lea rdx, [msg_pc]
    mov r8d, 5
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print PC value
    mov eax, [rv_pc]
    lea rdi, [num_buf]
    call .print_hex
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 8
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print t1 (x6)
    lea rax, [rv_regs]
    mov eax, [rax + 6*8]
    lea rdi, [num_buf]
    call .print_hex
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 8
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

    ; Run one more block
    mov rdi, [rv_pc]           ; continue from current PC
    mov rsi, [guest_memory]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8d, 1
    call execute_blocks

    inc qword [block_count]
    cmp qword [block_count], 262170
    jl .trace_loop

    mov ecx, 0
    jmp .exit

.fail:
    mov ecx, 255

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
