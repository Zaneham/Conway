; doom_runner_simple.asm - Minimal test to track elf_buffer corruption
bits 64
default rel

extern load_elf
extern get_elf_entry_point
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
extern elf_brk_base
extern elf_tls_base
extern elf_load_base
extern elf_phoff
extern elf_phentsize
extern elf_phnum
extern stdout_handle
extern bytes_written
extern high_store_count

; Auxiliary vector types for Linux ABI
AT_NULL         equ 0
AT_PHDR         equ 3
AT_PHENT        equ 4
AT_PHNUM        equ 5

PAGE_EXECUTE_READWRITE  equ 0x40
MEM_COMMIT              equ 0x1000
MEM_RESERVE             equ 0x2000
GENERIC_READ            equ 0x80000000
FILE_SHARE_READ         equ 1
OPEN_EXISTING           equ 3
FILE_ATTRIBUTE_NORMAL   equ 0x80
INVALID_HANDLE_VALUE    equ -1
STD_OUTPUT_HANDLE       equ -11

section .data
    default_path    db "C:\\dev\\conway\\doomgeneric\\doomgeneric\\doom_conway.elf", 0
    doom_str        db "doom", 0
    iwad_str        db "-iwad", 0
    wad_str         db "C:\\dev\\conway\\test\\doom1.wad", 0
    ; Debug messages
    msg_alloc_ok    db "Alloc OK", 10, 0
    msg_open_ok     db "Open OK", 10, 0
    msg_read_ok     db "Read OK: ", 0
    msg_load_ok     db "Load OK, BRK:", 0
    msg_exec        db "Starting execution...", 10, 0
    msg_fail        db "FAIL", 10, 0
    ; Variables in .data to avoid BSS issues
    alignb 8
    file_handle     dq 0
    bytes_read      dq 0
    elf_buffer      dq 0
    guest_memory    dq 0
    old_protect     dd 0
    alignb 8
    rv_regs         times 32 dq 0
    rv_fp_regs      times 32 dq 0
    rv_pc           dq 0
    elf_path        dq 0
    entry_point     dq 0
    num_buf         times 32 db 0

section .text
    global main

; Print string (rcx=handle, rdx=string, r8=len)
print_str:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    lea r9, [bytes_written]     ; Use proper output, not num_buf!
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rbp
    ret

; Print hex (rax=value, rdi=buffer, ecx=digits)
print_hex:
.loop:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .digit
    add dl, 'A' - 10
    jmp .store
.digit:
    add dl, '0'
.store:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .loop
    ret

main:
    push rbp
    mov rbp, rsp
    sub rsp, 128

    ; Get stdout
    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [stdout_handle], rax

    ; Allocate 8MB for ELF buffer
    xor ecx, ecx
    mov edx, 8*1024*1024
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_EXECUTE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz .fail
    mov [elf_buffer], rax

    ; Allocate 128MB for guest memory
    xor ecx, ecx
    mov edx, 128*1024*1024
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_EXECUTE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz .fail
    mov [guest_memory], rax

    ; Print "Alloc OK"
    mov rcx, [stdout_handle]
    lea rdx, [msg_alloc_ok]
    mov r8d, 9
    call print_str

    ; VirtualProtect on code buffer
    lea rcx, [code_buffer]
    mov edx, 2*1024*1024
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    ; Set elf_path
    lea rax, [default_path]
    mov [elf_path], rax

    ; Open ELF file
    mov rcx, [elf_path]
    mov edx, GENERIC_READ
    mov r8d, FILE_SHARE_READ
    xor r9d, r9d
    mov qword [rsp+32], OPEN_EXISTING
    mov qword [rsp+40], FILE_ATTRIBUTE_NORMAL
    mov qword [rsp+48], 0
    call CreateFileA
    cmp rax, INVALID_HANDLE_VALUE
    je .fail
    mov [file_handle], rax

    ; Print "Open OK"
    mov rcx, [stdout_handle]
    lea rdx, [msg_open_ok]
    mov r8d, 8
    call print_str

    ; Debug: print elf_buffer before ReadFile
    mov byte [num_buf], 'E'
    mov byte [num_buf+1], 'B'
    mov byte [num_buf+2], ':'
    mov rax, [elf_buffer]
    lea rdi, [num_buf+3]
    mov ecx, 16
    call print_hex
    mov byte [num_buf+19], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 20
    call print_str

    ; Read file - USE THE VALUE DIRECTLY from memory
    mov rcx, [file_handle]
    mov rdx, [elf_buffer]       ; This should be ~0x1BA0000
    mov r8d, 8*1024*1024
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call ReadFile
    test eax, eax
    jz .fail

    ; Print "Read OK: " + bytes_read
    mov rcx, [stdout_handle]
    lea rdx, [msg_read_ok]
    mov r8d, 9
    call print_str

    ; Print bytes_read as hex (32-bit value, shift to upper 32 bits for print_hex)
    mov eax, [bytes_read]
    shl rax, 32                 ; Move to upper 32 bits for rotation-based print
    lea rdi, [num_buf]
    mov ecx, 8
    call print_hex
    mov byte [num_buf+8], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 9
    call print_str

    ; Close file
    mov rcx, [file_handle]
    call CloseHandle

    ; Init block cache
    call init_block_cache

    ; Load ELF
    mov rdi, [elf_buffer]
    mov rsi, [bytes_read]
    mov rdx, [guest_memory]
    mov rcx, 128*1024*1024
    call load_elf
    test eax, eax
    jnz .fail

    ; Print "Load OK, BRK:" + brk value
    mov rcx, [stdout_handle]
    lea rdx, [msg_load_ok]
    mov r8d, 13
    call print_str

    mov rax, [elf_brk_base]
    shl rax, 32                 ; Move to upper 32 bits for rotation-based print
    lea rdi, [num_buf]
    mov ecx, 8
    call print_hex
    mov byte [num_buf+8], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 9
    call print_str

    ; Debug: Print heap_ptr value at guest address 0x68688
    mov byte [num_buf], 'H'
    mov byte [num_buf+1], 'P'
    mov byte [num_buf+2], ':'
    mov rdi, [guest_memory]
    mov rax, [rdi + 0x68688]    ; Load heap_ptr from guest memory
    lea rdi, [num_buf+3]
    mov ecx, 16
    call print_hex
    mov byte [num_buf+19], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 20
    call print_str

    ; Set up argv in guest memory
    ; Place argv area HIGH in memory to avoid collision with heap
    ; Guest has 128MB = 0x8000000, put argv near 120MB = 0x7800000
    ; "doom" at 0x7800000, "-iwad" at 0x7800010, "doom1.wad" at 0x7800020
    mov rdi, [guest_memory]

    ; Copy "doom"
    lea rsi, [doom_str]
    lea rax, [rdi + 0x7800000]
    mov rdi, rax
    mov rcx, 5
    rep movsb
    mov rdi, [guest_memory]

    ; Copy "-iwad"
    lea rsi, [iwad_str]
    lea rax, [rdi + 0x7800010]
    mov rdi, rax
    mov rcx, 6
    rep movsb
    mov rdi, [guest_memory]

    ; Copy WAD path (absolute)
    lea rsi, [wad_str]
    lea rax, [rdi + 0x7800020]
    mov rdi, rax
    mov rcx, 30                         ; "C:\dev\conway\test\doom1.wad" + null
    rep movsb
    mov rdi, [guest_memory]

    ; Set up argv array at 0x7800100 (original working setup)
    mov qword [rdi + 0x7800100], 3            ; argc = 3
    mov qword [rdi + 0x7800108], 0x7800000    ; argv[0] = "doom"
    mov qword [rdi + 0x7800110], 0x7800010    ; argv[1] = "-iwad"
    mov qword [rdi + 0x7800118], 0x7800020    ; argv[2] = "doom1.wad"
    mov qword [rdi + 0x7800120], 0            ; argv[3] = NULL

    ; Clear registers
    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 32
.clr_regs:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .clr_regs

    ; Clear FP registers
    lea rdi, [rv_fp_regs]
    mov ecx, 32
.clr_fp:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .clr_fp

    ; Set up initial register state
    ; SP at 127MB = 0x7F00000 to give heap room to grow
    lea rax, [rv_regs]
    mov rdi, [guest_memory]
    mov qword [rax + 2*8], 0x7F00000        ; sp = stack pointer
    ; Initialize TP (x4) to point to TLS block for newlib thread-local storage
    mov rcx, [elf_tls_base]
    mov qword [rax + 4*8], rcx              ; tp = TLS base
    mov qword [rax + 10*8], 3               ; a0 = argc
    mov qword [rax + 11*8], 0x7800108       ; a1 = &argv[0]

    ; Debug: Print TP value (TLS base)
    mov byte [num_buf], 'T'
    mov byte [num_buf+1], 'P'
    mov byte [num_buf+2], ':'
    mov rax, [elf_tls_base]
    lea rdi, [num_buf+3]
    mov ecx, 16
    call print_hex
    mov byte [num_buf+19], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 20
    call print_str

    ; Print guest_memory before execution (HP:XXXXXXXX)
    mov byte [num_buf], 'H'
    mov byte [num_buf+1], 'P'
    mov byte [num_buf+2], ':'
    mov rax, [guest_memory]
    lea rdi, [num_buf+3]
    mov ecx, 16
    call print_hex
    mov byte [num_buf+19], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 20
    call print_str

    ; Test: print 2 bytes from guest_memory + 0x91500 (iwad names "doom2.wad")
    mov byte [num_buf], 'I'
    mov byte [num_buf+1], 'W'
    mov byte [num_buf+2], ':'
    mov rdi, [guest_memory]
    add rdi, 0x91500                ; iwad name area in guest memory
    movzx eax, byte [rdi]           ; First byte - should be 'T' = 0x54
    mov edx, eax
    shr edx, 4
    add dl, '0'
    cmp dl, '9'
    jbe .tr0h
    add dl, 7
.tr0h:
    mov [num_buf+3], dl
    and al, 0xF
    add al, '0'
    cmp al, '9'
    jbe .tr0l
    add al, 7
.tr0l:
    mov [num_buf+4], al
    movzx eax, byte [rdi+1]         ; Second byte - should be 'r' = 0x72
    mov edx, eax
    shr edx, 4
    add dl, '0'
    cmp dl, '9'
    jbe .tr1h
    add dl, 7
.tr1h:
    mov [num_buf+5], dl
    and al, 0xF
    add al, '0'
    cmp al, '9'
    jbe .tr1l
    add al, 7
.tr1l:
    mov [num_buf+6], al
    mov byte [num_buf+7], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 8
    call print_str

    ; Print "Starting execution..."
    mov rcx, [stdout_handle]
    lea rdx, [msg_exec]
    mov r8d, 22
    call print_str

    ; Get entry point and execute
    call get_elf_entry_point
    mov edi, eax                            ; Start PC
    mov rsi, [guest_memory]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    xor r8d, r8d                            ; 0 = unlimited blocks
    lea r9, [rv_fp_regs]
    call execute_blocks

    ; Print high address store count
    mov byte [num_buf], 'H'
    mov byte [num_buf+1], 'S'
    mov byte [num_buf+2], ':'
    mov rax, [high_store_count]
    shl rax, 32                 ; Move to upper 32 bits for rotation-based print
    lea rdi, [num_buf+3]
    mov ecx, 8
.hs_loop:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .hs_digit
    add dl, 'A' - 10
    jmp .hs_store
.hs_digit:
    add dl, '0'
.hs_store:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .hs_loop
    mov byte [num_buf+11], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 12
    call print_str

    ; Get exit code from a0 (x10)
    mov ecx, [rv_regs + 10*8]
    call ExitProcess

.fail:
    mov rcx, [stdout_handle]
    lea rdx, [msg_fail]
    mov r8d, 5
    call print_str
    mov ecx, 1
    call ExitProcess
