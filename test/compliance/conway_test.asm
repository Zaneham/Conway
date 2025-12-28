; conway_test.asm - Conway compliance test runner
; Accepts an ELF file path as command line argument
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
extern GetStdHandle
extern WriteFile

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
    elf_buffer      resb 2097152    ; 2MB for ELF files
    guest_memory    resb 2097152    ; 2MB guest memory
    rv_regs         resq 32
    rv_fp_regs      resq 32         ; FP register file (f0-f31)
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

    ; Get command line using Windows API
    call GetCommandLineA
    mov rsi, rax

    ; Skip past executable name to find argument
.skip_exe:
    lodsb
    test al, al
    jz .use_default             ; No argument found
    cmp al, ' '
    jne .skip_exe
    ; Skip spaces
.skip_spaces:
    lodsb
    cmp al, ' '
    je .skip_spaces
    test al, al
    jz .use_default             ; Only spaces after exe name
    ; Handle quoted path - skip opening quote
    cmp al, '"'
    jne .no_quote
    mov [elf_path], rsi         ; Path starts after the quote
    ; Find and null-terminate at closing quote
.find_close_quote:
    lodsb
    test al, al
    jz .start_execution         ; No closing quote, use as-is
    cmp al, '"'
    jne .find_close_quote
    mov byte [rsi-1], 0         ; Null-terminate at the closing quote
    jmp .start_execution
.no_quote:
    dec rsi                     ; Back up to first non-space
    mov [elf_path], rsi
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
    mov r8d, 2097152            ; 2MB max
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call ReadFile

    ; Close file
    mov rcx, [file_handle]
    call CloseHandle

    ; Load ELF
    ; load_elf(elf_data, elf_size, guest_mem, guest_size)
    lea rdi, [elf_buffer]
    mov rsi, [bytes_read]
    lea rdx, [guest_memory]
    mov rcx, 2097152            ; 2MB guest memory
    call load_elf
    test eax, eax
    jnz .load_error

    ; Clear integer registers
    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 32
.clr:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .clr

    ; Clear FP registers
    lea rdi, [rv_fp_regs]
    mov ecx, 32
.clr_fp:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .clr_fp

    ; Execute
    ; execute_blocks(start_pc, guest_mem, rv_regs, rv_pc_ptr, max_blocks, fp_regs)
    call get_elf_entry_point    ; Get actual entry point from ELF
    mov edi, eax                ; Start PC at ELF entry point
    lea rsi, [guest_memory]     ; Guest memory base
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    xor r8d, r8d                ; 0 = unlimited blocks
    lea r9, [rv_fp_regs]        ; FP register file
    call execute_blocks

    ; DEBUG: If we get here, execute_blocks returned unexpectedly
    ; Print "RET" marker
    sub rsp, 48
    mov byte [rsp], 'R'
    mov byte [rsp+1], 'E'
    mov byte [rsp+2], 'T'
    mov byte [rsp+3], ':'
    ; Print a0 as hex
    mov eax, [rv_regs + 10*8]
    mov ecx, eax
    shr ecx, 4
    and ecx, 0xF
    cmp cl, 10
    jb .ret_d1
    add cl, 'A' - 10
    jmp .ret_s1
.ret_d1:
    add cl, '0'
.ret_s1:
    mov [rsp+4], cl
    mov ecx, eax
    and ecx, 0xF
    cmp cl, 10
    jb .ret_d2
    add cl, 'A' - 10
    jmp .ret_s2
.ret_d2:
    add cl, '0'
.ret_s2:
    mov [rsp+5], cl
    mov byte [rsp+6], 10

    sub rsp, 32
    mov rcx, -11
    call GetStdHandle
    mov rcx, rax
    lea rdx, [rsp+32]
    mov r8d, 7
    lea r9, [rsp+24]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 32
    add rsp, 48
    ; END DEBUG

    ; Get exit code from a0 (x10)
    mov ecx, [rv_regs + 10*8]
    call quick_exit

.file_error:
    mov ecx, 100
    call quick_exit

.load_error:
    mov ecx, 101
    call quick_exit
