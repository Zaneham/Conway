; test_real_elf_run.asm - Load and execute a real RISC-V ELF binary
; "It works! It actually works!" - Every developer, eventually
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
extern elf_tls_base
extern elf_load_base
extern elf_brk_base
extern elf_phoff
extern elf_phnum
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
    test_msg        db "TEST OUTPUT", 10, 0

section .bss
    elf_path        resq 1              ; Pointer to path (cmdline arg or default)
    old_protect     resd 1
    alignb 8
    file_handle     resq 1
    bytes_read      resq 1
    bytes_written   resq 1              ; For WriteFile output
    stdout_handle   resq 1              ; For debug output
    elf_buffer      resb 8*1024*1024       ; 8MB for ELF file
    guest_memory    resb 128*1024*1024     ; 128MB for guest memory
    rv_regs         resq 32
    rv_fp_regs      resq 32
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

    ; Test stdout output first
    mov ecx, -11                    ; STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [stdout_handle], rax

    sub rsp, 48
    mov rcx, [stdout_handle]
    lea rdx, [test_msg]
    mov r8d, 12                     ; "TEST OUTPUT\n"
    lea r9, [bytes_written]
    mov qword [rsp+32], 0           ; overlapped = NULL
    call WriteFile
    add rsp, 48

    ; Parse command line - get ELF path from args or use default
    call GetCommandLineA        ; Returns pointer to command line in RAX
    mov rdi, rax

    ; Skip program name (possibly quoted)
    cmp byte [rdi], '"'
    jne .skip_unquoted
    ; Quoted - skip until closing quote
    inc rdi
.skip_quoted:
    cmp byte [rdi], 0
    je .use_default
    cmp byte [rdi], '"'
    je .after_quote
    inc rdi
    jmp .skip_quoted
.after_quote:
    inc rdi                     ; Skip closing quote
    jmp .skip_spaces

.skip_unquoted:
    ; Unquoted - skip until space or end
    cmp byte [rdi], 0
    je .use_default
    cmp byte [rdi], ' '
    je .skip_spaces
    inc rdi
    jmp .skip_unquoted

.skip_spaces:
    ; Skip spaces between program name and first arg
    cmp byte [rdi], ' '
    jne .check_arg
    inc rdi
    jmp .skip_spaces

.check_arg:
    ; Check if we have an argument
    cmp byte [rdi], 0
    je .use_default
    ; We have an argument - use it as path
    mov [elf_path], rdi
    jmp .path_ready

.use_default:
    lea rax, [default_path]
    mov [elf_path], rax

.path_ready:
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
    mov rcx, [elf_path]         ; Load pointer to path string
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
    mov r8d, 8*1024*1024           ; 8MB max ELF size
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
    mov rcx, 128*1024*1024         ; 128MB guest memory
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

    ; Clear FP registers
    lea rdi, [rv_fp_regs]
    xor eax, eax
    mov ecx, 32
.clr_fp:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .clr_fp

    ; Set up stack and registers for program execution
    lea rdi, [guest_memory]
    lea rax, [rv_regs]

    ; Set SP at high address
    mov qword [rax + 2*8], 0x7F00000       ; sp = 127MB

    ; Set up TP (thread pointer) for TLS
    mov rcx, [elf_tls_base]
    mov qword [rax + 4*8], rcx             ; tp (x4) = TLS base

    ; Print checkpoint before _dl_phdr setup
    sub rsp, 48
    mov byte [rsp+40], 'C'
    mov byte [rsp+41], 'K'
    mov byte [rsp+42], '1'
    mov byte [rsp+43], 10
    mov rcx, [stdout_handle]
    lea rdx, [rsp+40]
    mov r8d, 4
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    lea rax, [rv_regs]              ; Restore rax

    ; Set _dl_phdr and _dl_phnum for proper TLS initialization
    ; _dl_phnum is at 0x70BC0, _dl_phdr is at 0x70BC8

    ; Disable _dl_phdr - let initial TP point directly to template
    ; This means libc won't reallocate TLS, TP stays at template address
    ; (This is a hack to test if template location works directly)
    ; lea rdi, [guest_memory]
    ; mov rsi, [elf_load_base]
    ; add rsi, [elf_phoff]
    ; mov qword [rdi + 0x70BC8], rsi  ; _dl_phdr
    ; mov rcx, [elf_phnum]
    ; mov qword [rdi + 0x70BC0], rcx  ; _dl_phnum

    ; Checkpoint 2 - after writes
    sub rsp, 48
    mov byte [rsp+40], 'C'
    mov byte [rsp+41], 'K'
    mov byte [rsp+42], '2'
    mov byte [rsp+43], 10
    mov rcx, [stdout_handle]
    lea rdx, [rsp+40]
    mov r8d, 4
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48

    ; Print what we set (DEBUG)
    sub rsp, 48
    mov byte [rsp+40], 'P'
    mov byte [rsp+41], 'H'
    mov byte [rsp+42], '='
    mov rax, rsi                    ; phdr address
    shl rax, 32                     ; Move to upper 32 bits for rotation
    lea rdi, [rsp+43]
    mov ecx, 8
.phdr_hex:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .phdr_d
    add dl, 'A' - 10
    jmp .phdr_s
.phdr_d:
    add dl, '0'
.phdr_s:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .phdr_hex
    mov byte [rsp+51], 10
    mov rcx, [stdout_handle]
    lea rdx, [rsp+40]
    mov r8d, 12
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48

    ; Checkpoint 3 - before execution
    sub rsp, 48
    mov byte [rsp+40], 'C'
    mov byte [rsp+41], 'K'
    mov byte [rsp+42], '3'
    mov byte [rsp+43], 10
    mov rcx, [stdout_handle]
    lea rdx, [rsp+40]
    mov r8d, 4
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48

    ; Debug: Print first 8 bytes at TLS vaddr 0x6E4D0
    sub rsp, 48
    mov byte [rsp+40], 'T'
    mov byte [rsp+41], 'L'
    mov byte [rsp+42], 'S'
    mov byte [rsp+43], '='
    lea rdi, [guest_memory]
    mov rax, [rdi + 0x6E4D0]        ; First 8 bytes of TLS template
    lea rsi, [rsp+44]
    mov ecx, 16
.tls_dump_loop:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .tls_dump_digit
    add dl, 'A' - 10
    jmp .tls_dump_store
.tls_dump_digit:
    add dl, '0'
.tls_dump_store:
    mov [rsi], dl
    inc rsi
    dec ecx
    jnz .tls_dump_loop
    mov byte [rsp+60], 10
    mov rcx, [stdout_handle]
    lea rdx, [rsp+40]
    mov r8d, 21
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48

    lea rdi, [guest_memory]         ; FIX: use LEA not MOV
    lea rax, [rv_regs]

    ; Pre-copy TLS template to where TP will end up
    ; NOTE: Hardcoded for strncasecmp_simple.elf
    ; Source: 0x6E4D0 (TLS template vaddr)
    ; Dest: 0x767A0 (where newlib sets TP = brk_init - 0x330)
    lea r12, [guest_memory]
    lea rsi, [r12 + 0x6E4D0]        ; Source: TLS template
    lea rdi, [r12 + 0x767A0]        ; Dest: TP address
    mov ecx, 4                      ; 4 qwords = 32 bytes
.tls_exact_copy:
    mov rax, [rsi]
    mov [rdi], rax
    add rsi, 8
    add rdi, 8
    dec ecx
    jnz .tls_exact_copy
    lea rax, [rv_regs]

    ; Debug: Print initial TP (before execution)
    sub rsp, 48
    mov byte [rsp+40], 'I'
    mov byte [rsp+41], 'T'
    mov byte [rsp+42], 'P'
    mov byte [rsp+43], '='
    mov r12, [rax + 4*8]           ; Save initial TP value
    shl r12, 32
    lea rdi, [rsp+44]
    mov ecx, 8
.itp_loop:
    rol r12, 4
    mov edx, r12d
    and edx, 0xF
    cmp dl, 10
    jb .itp_digit
    add dl, 'A' - 10
    jmp .itp_store
.itp_digit:
    add dl, '0'
.itp_store:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .itp_loop
    mov byte [rsp+52], 10
    mov rcx, [stdout_handle]
    lea rdx, [rsp+40]
    mov r8d, 13
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    lea rax, [rv_regs]

    ; Execute
    call get_elf_entry_point
    mov edi, eax                    ; Start PC from ELF entry point
    lea rsi, [guest_memory]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    xor r8d, r8d                    ; 0 = unlimited blocks
    lea r9, [rv_fp_regs]            ; FP registers
    call execute_blocks

    ; DEBUG: Print "DONE" to verify we get here
    sub rsp, 48
    mov rcx, [stdout_handle]
    mov byte [rsp+40], 'D'
    mov byte [rsp+41], 'O'
    mov byte [rsp+42], 'N'
    mov byte [rsp+43], 'E'
    mov byte [rsp+44], 10
    lea rdx, [rsp+40]
    mov r8d, 5
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48

    ; === CHECKPOINT 9 ===
    ; DEBUG: Print final TP value (x4)
    lea rax, [rv_regs]
    mov r12, [rax + 4*8]            ; TP = x4, save in r12

    ; Get stdout handle
    mov ecx, -11
    sub rsp, 40
    call GetStdHandle
    add rsp, 40
    mov [stdout_handle], rax

    ; Build "TP=XXXXXXXXXXXXXXXX\n" in stack buffer
    ; Layout: [rsp+0..31]=shadow, [rsp+32..63]=buffer
    sub rsp, 96                     ; extra space: shadow + buffer + padding
    mov byte [rsp+64], 'T'
    mov byte [rsp+65], 'P'
    mov byte [rsp+66], '='

    ; Convert TP to hex
    lea rdi, [rsp+67]
    mov rax, r12
    mov ecx, 16
.tp_hex_loop:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .tp_digit
    add dl, 'A' - 10
    jmp .tp_store
.tp_digit:
    add dl, '0'
.tp_store:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .tp_hex_loop
    mov byte [rsp+83], 10           ; newline

    ; Write to stdout
    mov rcx, [stdout_handle]
    lea rdx, [rsp+64]               ; buffer
    mov r8d, 20                     ; length
    lea r9, [bytes_written]
    mov qword [rsp+32], 0           ; overlapped = NULL (in shadow area)
    call WriteFile
    add rsp, 96

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
