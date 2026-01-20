; entry_win.asm - Windows entry point for Conway
; Links together: platform_win.asm, elf_loader.asm, translator.asm

bits 64
default rel

; Windows API
extern GetCommandLineA
extern CreateFileA
extern ReadFile
extern GetFileSize
extern CloseHandle
extern VirtualAlloc
extern VirtualFree
extern ExitProcess
extern GetStdHandle
extern WriteFile
extern VirtualProtect

; Platform functions
extern plat_init
extern plat_exit

; ELF loader functions
extern load_elf
extern elf_entry_point
extern elf_load_base
extern elf_brk_base

; Translator functions
extern init_block_cache
extern execute_blocks
extern code_buffer

; Export main for linker
global main

; Code buffer size (must match translator.asm)
CODE_BUFFER_SIZE    equ 16777216

;==============================================================================
; Constants
;==============================================================================
GUEST_MEM_SIZE      equ 0x10000000      ; 256 MB guest memory
FILE_SHARE_READ     equ 1
OPEN_EXISTING       equ 3
GENERIC_READ        equ 0x80000000
MEM_COMMIT          equ 0x1000
MEM_RESERVE         equ 0x2000
PAGE_READWRITE      equ 0x04
PAGE_EXECUTE_READWRITE equ 0x40
INVALID_HANDLE      equ -1

section .data
    banner      db "Conway - RISC-V to x86-64 Binary Translator", 13, 10, 0
    banner_len  equ $ - banner - 1
    usage_msg   db "Usage: conway <riscv_elf>", 13, 10, 0
    usage_len   equ $ - usage_msg - 1
    err_open    db "Error: Could not open file", 13, 10, 0
    err_open_len equ $ - err_open - 1
    err_read    db "Error: Could not read file", 13, 10, 0
    err_read_len equ $ - err_read - 1
    err_mem     db "Error: Memory allocation failed", 13, 10, 0
    err_mem_len equ $ - err_mem - 1
    err_elf     db "Error: Invalid ELF file", 13, 10, 0
    err_elf_len equ $ - err_elf - 1
    ok_loaded   db "ELF loaded, starting execution...", 13, 10, 0
    ok_len      equ $ - ok_loaded - 1

section .bss
    cmdline     resq 1
    arg1_start  resq 1
    file_handle resq 1
    old_protect resd 1
    file_size   resq 1
    file_buffer resq 1
    guest_mem   resq 1
    rv_regs     resq 32         ; RISC-V x0-x31
    rv_pc       resq 1          ; Program counter
    rv_fp_regs  resq 32         ; FP registers (f0-f31)
    bytes_read  resd 1
    stdout_h    resq 1

section .text

;==============================================================================
; main - Entry point
; Windows x64 ABI: RCX=argc equivalent, RDX=argv equivalent (but we use GetCommandLine)
;==============================================================================
main:
    push rbp
    mov rbp, rsp
    sub rsp, 64                     ; Local space + shadow space

    ; Get stdout handle for messages
    mov ecx, -11                    ; STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [stdout_h], rax

    ; Print banner
    mov rcx, [stdout_h]
    lea rdx, [banner]
    mov r8d, banner_len
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call WriteFile

    ; Initialize platform (sets up stdout_handle in platform_win.asm)
    call plat_init

    ; Get command line (narrow/ANSI string)
    call GetCommandLineA
    mov [cmdline], rax

    ; Parse command line to find argv[1]
    ; Format: "program.exe" arg1 arg2 ... or program.exe arg1 arg2 ...
    mov rsi, rax

    ; Skip leading whitespace
.skip_ws1:
    mov al, [rsi]
    test al, al
    jz .show_usage
    cmp al, ' '
    je .next_ws1
    cmp al, 9                       ; Tab
    jne .check_quote
.next_ws1:
    inc rsi
    jmp .skip_ws1

.check_quote:
    ; Check if program name is quoted
    cmp al, '"'
    jne .skip_program

    ; Skip quoted program name
    inc rsi
.skip_quoted:
    mov al, [rsi]
    test al, al
    jz .show_usage
    cmp al, '"'
    je .end_quoted
    inc rsi
    jmp .skip_quoted
.end_quoted:
    inc rsi                         ; Skip closing quote
    jmp .skip_ws2

.skip_program:
    ; Skip unquoted program name
    mov al, [rsi]
    test al, al
    jz .show_usage
    cmp al, ' '
    je .skip_ws2
    cmp al, 9
    je .skip_ws2
    inc rsi
    jmp .skip_program

.skip_ws2:
    ; Skip whitespace before arg1
    mov al, [rsi]
    test al, al
    jz .show_usage
    cmp al, ' '
    je .next_ws2
    cmp al, 9
    jne .found_arg1
.next_ws2:
    inc rsi
    jmp .skip_ws2

.found_arg1:
    ; rsi now points to argv[1]
    mov [arg1_start], rsi

    ; Open file using arg1
    mov rcx, rsi                    ; lpFileName
    mov edx, GENERIC_READ           ; dwDesiredAccess
    mov r8d, FILE_SHARE_READ        ; dwShareMode
    xor r9d, r9d                    ; lpSecurityAttributes
    mov dword [rsp+32], OPEN_EXISTING ; dwCreationDisposition
    mov dword [rsp+40], 0           ; dwFlagsAndAttributes
    mov qword [rsp+48], 0           ; hTemplateFile
    call CreateFileA
    cmp rax, INVALID_HANDLE
    je .err_open
    mov [file_handle], rax

    ; Get file size
    mov rcx, rax
    xor edx, edx
    call GetFileSize
    mov [file_size], rax

    ; Allocate buffer for file
    xor ecx, ecx                    ; lpAddress
    mov rdx, [file_size]            ; dwSize
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz .err_mem
    mov [file_buffer], rax

    ; Read file
    mov rcx, [file_handle]
    mov rdx, [file_buffer]
    mov r8d, dword [file_size]
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call ReadFile
    test eax, eax
    jz .err_read

    ; Close file handle
    mov rcx, [file_handle]
    call CloseHandle

    ; Allocate guest memory
    xor ecx, ecx
    mov edx, GUEST_MEM_SIZE
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_EXECUTE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz .err_mem
    mov [guest_mem], rax

    ; Load ELF into guest memory
    ; load_elf(elf_data, elf_size, guest_base, guest_size)
    mov rdi, [file_buffer]
    mov rsi, [file_size]
    mov rdx, [guest_mem]
    mov rcx, GUEST_MEM_SIZE
    call load_elf
    test eax, eax
    jnz .err_elf

    ; Initialize block cache
    call init_block_cache

    ; Make code_buffer executable
    ; VirtualProtect(code_buffer, CODE_BUFFER_SIZE, PAGE_EXECUTE_READWRITE, &old_protect)
    lea rcx, [code_buffer]
    mov edx, CODE_BUFFER_SIZE
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect
    test eax, eax
    jz .err_mem                     ; VirtualProtect failed

    ; Print success message
    mov rcx, [stdout_h]
    lea rdx, [ok_loaded]
    mov r8d, ok_len
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call WriteFile

    ; Zero out register file
    lea rdi, [rv_regs]
    mov ecx, 32
    xor eax, eax
.zero_regs:
    mov [rdi + rcx*8 - 8], rax
    loop .zero_regs

    ; Set up stack pointer (x2/sp) - point to end of guest memory
    mov rax, [guest_mem]
    add rax, GUEST_MEM_SIZE - 4096  ; Leave some headroom
    mov [rv_regs + 2*8], rax        ; x2 = sp

    ; Execute translated blocks
    ; execute_blocks(start_pc, guest_mem, rv_regs, &rv_pc, max_blocks, fp_regs)
    mov rdi, [elf_entry_point]
    mov rsi, [guest_mem]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    xor r8d, r8d                    ; Unlimited blocks
    lea r9, [rv_fp_regs]
    call execute_blocks

    ; Return value in a0 (x10) as exit code
    mov eax, dword [rv_regs + 10*8]
    jmp .exit

.show_usage:
    mov rcx, [stdout_h]
    lea rdx, [usage_msg]
    mov r8d, usage_len
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call WriteFile
    mov eax, 1
    jmp .exit

.err_open:
    mov rcx, [stdout_h]
    lea rdx, [err_open]
    mov r8d, err_open_len
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call WriteFile
    mov eax, 2
    jmp .exit

.err_read:
    mov rcx, [stdout_h]
    lea rdx, [err_read]
    mov r8d, err_read_len
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call WriteFile
    mov eax, 3
    jmp .exit

.err_mem:
    mov rcx, [stdout_h]
    lea rdx, [err_mem]
    mov r8d, err_mem_len
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call WriteFile
    mov eax, 4
    jmp .exit

.err_elf:
    mov rcx, [stdout_h]
    lea rdx, [err_elf]
    mov r8d, err_elf_len
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call WriteFile
    mov eax, 5
    jmp .exit

.exit:
    add rsp, 64
    pop rbp
    ret
