; test_linux.asm - Linux test harness for Conway
; Build: nasm -f elf64 -o test_linux.o test_linux.asm
;        nasm -f elf64 -o translator.o ../src/translator.asm
;        nasm -f elf64 -o elf_loader.o ../src/elf_loader.asm
;        nasm -f elf64 -o platform_linux.o ../src/platform_linux.asm
;        ld -o conway test_linux.o translator.o elf_loader.o platform_linux.o

bits 64
default rel

; Conway exports
extern load_elf
extern elf_entry_point
extern init_block_cache
extern execute_blocks
extern code_buffer

; Platform exports
extern plat_init
extern plat_exit
extern plat_make_executable

; Linux syscall numbers
SYS_READ        equ 0
SYS_WRITE       equ 1
SYS_OPEN        equ 2
SYS_CLOSE       equ 3
SYS_EXIT        equ 60

; open() flags
O_RDONLY        equ 0

; File descriptors
STDOUT          equ 1
STDERR          equ 2

section .bss
    alignb 8
    file_handle     resq 1
    bytes_read      resq 1
    elf_buffer      resb 2097152      ; 2MB for ELF files
    guest_memory    resb 2097152      ; 2MB guest memory
    rv_regs         resq 32
    rv_pc           resq 1
    argc_save       resq 1
    argv_save       resq 1

section .data
    err_usage       db "Usage: conway <riscv_binary>", 10, 0
    err_usage_len   equ $ - err_usage
    err_open        db "Error: Cannot open file", 10, 0
    err_open_len    equ $ - err_open
    err_load        db "Error: Failed to load ELF", 10, 0
    err_load_len    equ $ - err_load
    msg_pass        db "PASS", 10, 0
    msg_pass_len    equ $ - msg_pass
    msg_fail        db "FAIL", 10, 0
    msg_fail_len    equ $ - msg_fail

section .text
    global _start

_start:
    ; Linux passes: [rsp] = argc, [rsp+8] = argv[0], [rsp+16] = argv[1], ...
    mov rax, [rsp]                  ; argc
    mov [argc_save], rax
    lea rax, [rsp+8]                ; argv
    mov [argv_save], rax

    ; Initialize platform
    call plat_init

    ; Make code buffer executable
    lea rcx, [code_buffer]
    mov rdx, 1048576                ; 1MB
    call plat_make_executable

    ; Initialize block cache
    call init_block_cache

    ; Check argc >= 2
    mov rax, [argc_save]
    cmp rax, 2
    jl .usage_error

    ; Get argv[1] = filename
    mov rax, [argv_save]
    mov rdi, [rax+8]                ; argv[1]

    ; Open file: open(filename, O_RDONLY)
    mov eax, SYS_OPEN
    ; rdi = filename (already set)
    xor esi, esi                    ; O_RDONLY
    xor edx, edx                    ; mode (ignored for O_RDONLY)
    syscall

    test rax, rax
    js .open_error
    mov [file_handle], rax

    ; Read file: read(fd, buf, count)
    mov eax, SYS_READ
    mov rdi, [file_handle]
    lea rsi, [elf_buffer]
    mov rdx, 2097152                ; Read up to 2MB
    syscall

    test rax, rax
    js .read_error
    mov [bytes_read], rax

    ; Close file
    mov eax, SYS_CLOSE
    mov rdi, [file_handle]
    syscall

    ; Load ELF
    ; load_elf(elf_data, elf_size, guest_mem, guest_size)
    lea rdi, [elf_buffer]
    mov rsi, [bytes_read]
    lea rdx, [guest_memory]
    mov rcx, 2097152
    call load_elf

    test eax, eax
    jnz .load_error

    ; Clear RISC-V registers
    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 32
.clear_regs:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .clear_regs

    ; Execute translated code
    ; execute_blocks(start_pc, guest_mem, rv_regs, rv_pc_ptr, max_blocks)
    mov edi, 0x1000                 ; Start PC at ELF entry point (matches Windows)
    lea rsi, [guest_memory]         ; Guest memory base
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    xor r8d, r8d                    ; 0 = unlimited blocks
    call execute_blocks

    ; Get return value from a0 (x10)
    lea rax, [rv_regs]
    mov edi, [rax + 80]             ; x10 * 8 = 80

    ; Exit with a0 value
    mov eax, SYS_EXIT
    syscall

.usage_error:
    mov eax, SYS_WRITE
    mov edi, STDERR
    lea rsi, [err_usage]
    mov edx, err_usage_len
    syscall
    mov edi, 1
    mov eax, SYS_EXIT
    syscall

.open_error:
    mov eax, SYS_WRITE
    mov edi, STDERR
    lea rsi, [err_open]
    mov edx, err_open_len
    syscall
    mov edi, 2
    mov eax, SYS_EXIT
    syscall

.read_error:
.load_error:
    mov eax, SYS_WRITE
    mov edi, STDERR
    lea rsi, [err_load]
    mov edx, err_load_len
    syscall
    mov edi, 3
    mov eax, SYS_EXIT
    syscall
