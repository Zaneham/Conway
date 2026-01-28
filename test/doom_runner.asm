; doom_runner.asm - Minimal Doom runner with dynamic allocation
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
extern GetCommandLineA
extern stdout_handle
extern bytes_written
extern elf_brk_base

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
    default_path    db "doomgeneric/doomgeneric/doom_minimal.elf", 0
    msg_a           db "A", 10
    msg_b           db "B", 10
    msg_c           db "C", 10
    msg_d           db "D", 10
    msg_e           db "E", 10
    msg_f           db "F", 10
    msg_g           db "G", 10
    msg_h           db "H", 10
    msg_i           db "I", 10
    msg_j           db "J", 10
    msg_k           db "K", 10
    msg_l           db "L", 10
    doom_str        db "doom", 0
    iwad_str        db "-iwad", 0
    wad_str         db "doom1.wad", 0

section .data
    old_protect     dd 0
    alignb 8
    file_handle     dq 0
    bytes_read      dq 0
    elf_buffer      dq 0x12345678DEADBEEF  ; Initialize with known pattern
    guest_memory    dq 0
    rv_regs         times 32 dq 0
    rv_fp_regs      times 32 dq 0
    rv_pc           dq 0
    elf_path        dq 0
    entry_point     dq 0
    num_buf         times 32 db 0
    write_count     dq 0
    elf_buf_backup  dq 0x87654321BADDCAFE  ; Initialize with another known pattern

section .text
    global main

main:
    push rbp
    mov rbp, rsp
    sub rsp, 128            ; Stack frame

    ; VERY FIRST: Print initial values
    ; Get stdout first
    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [stdout_handle], rax

    ; Print initial elf_buffer value: "I1:XXXXXXXXXXXXXXXX\n"
    mov byte [num_buf], 'I'
    mov byte [num_buf+1], '1'
    mov byte [num_buf+2], ':'
    mov rax, [elf_buffer]
    lea rdi, [num_buf+3]
    mov ecx, 16
.i1_hex:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .i1_d
    add dl, 'A' - 10
    jmp .i1_s
.i1_d:
    add dl, '0'
.i1_s:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .i1_hex
    mov byte [rdi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 20
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print initial elf_buf_backup value: "I2:XXXXXXXXXXXXXXXX\n"
    mov byte [num_buf], 'I'
    mov byte [num_buf+1], '2'
    mov byte [num_buf+2], ':'
    mov rax, [elf_buf_backup]
    lea rdi, [num_buf+3]
    mov ecx, 16
.i2_hex:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .i2_d
    add dl, 'A' - 10
    jmp .i2_s
.i2_d:
    add dl, '0'
.i2_s:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .i2_hex
    mov byte [rdi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 20
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; Get stdout
    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [stdout_handle], rax

    ; Print "A"
    mov rcx, rax
    lea rdx, [msg_a]
    mov r8d, 2
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; Use default path
    lea rax, [default_path]
    mov [elf_path], rax

    ; Print "B"
    mov rcx, [stdout_handle]
    lea rdx, [msg_b]
    mov r8d, 2
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; Allocate 8MB for ELF buffer
    xor ecx, ecx
    mov edx, 8*1024*1024
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_EXECUTE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz .alloc_fail
    mov [elf_buffer], rax
    mov [elf_buf_backup], rax       ; Store backup copy

    ; Debug: Print elf_buffer immediately after set
    push rax
    mov byte [num_buf], 'V'
    mov byte [num_buf+1], 'A'
    mov byte [num_buf+2], ':'
    mov rax, [elf_buffer]
    lea rdi, [num_buf+3]
    mov ecx, 16
.va_hex:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .va_d
    add dl, 'A' - 10
    jmp .va_s
.va_d:
    add dl, '0'
.va_s:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .va_hex
    mov byte [rdi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 20
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile
    pop rax

    ; Print "C"
    mov rcx, [stdout_handle]
    lea rdx, [msg_c]
    mov r8d, 2
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; IMMEDIATE check after WriteFile - is elf_buffer still valid?
    mov rax, [elf_buffer]
    test rax, rax
    jnz .elf_buf_ok
    ; elf_buffer is 0! Print marker
    mov byte [num_buf], '!'
    mov byte [num_buf+1], '0'
    mov byte [num_buf+2], '!'
    mov byte [num_buf+3], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 4
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile
.elf_buf_ok:

    ; Skip EA:/GA: prints - they might be causing corruption
    ; Instead, just check if elf_buffer is still valid
    mov rax, [elf_buffer]
    test rax, rax
    jnz .eb_still_ok
    ; Corruption detected! Print marker
    mov byte [num_buf], 'X'
    mov byte [num_buf+1], '1'
    mov byte [num_buf+2], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 3
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile
.eb_still_ok:

    ; Also check elf_buffer value after Print C
    mov byte [num_buf], 'P'
    mov byte [num_buf+1], 'C'
    mov byte [num_buf+2], ':'
    mov rax, [elf_buffer]
    lea rdi, [num_buf+3]
    mov ecx, 8
.pc_hex:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .pc_d
    add dl, 'A' - 10
    jmp .pc_s
.pc_d:
    add dl, '0'
.pc_s:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .pc_hex
    mov byte [rdi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 12
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; Check backup: BK:
    mov byte [num_buf], 'B'
    mov byte [num_buf+1], 'K'
    mov byte [num_buf+2], ':'
    mov rax, [elf_buf_backup]
    lea rdi, [num_buf+3]
    mov ecx, 8
.bk_hex:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .bk_d
    add dl, 'A' - 10
    jmp .bk_s
.bk_d:
    add dl, '0'
.bk_s:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .bk_hex
    mov byte [rdi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 12
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; Allocate 128MB for guest memory
    xor ecx, ecx
    mov edx, 128*1024*1024
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_EXECUTE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz .alloc_fail

    ; Debug: print elf_buffer BEFORE storing guest_memory (B4:)
    push rax
    mov byte [num_buf], 'B'
    mov byte [num_buf+1], '4'
    mov byte [num_buf+2], ':'
    mov rax, [elf_buffer]
    lea rdi, [num_buf+3]
    mov ecx, 8
.b4_hex:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .b4_d
    add dl, 'A' - 10
    jmp .b4_s
.b4_d:
    add dl, '0'
.b4_s:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .b4_hex
    mov byte [rdi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 12
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile
    pop rax

    mov [guest_memory], rax

    ; Debug: print elf_buffer AFTER storing guest_memory (A4:)
    mov byte [num_buf], 'A'
    mov byte [num_buf+1], '4'
    mov byte [num_buf+2], ':'
    mov rax, [elf_buffer]
    lea rdi, [num_buf+3]
    mov ecx, 8
.a4_hex:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .a4_d
    add dl, 'A' - 10
    jmp .a4_s
.a4_d:
    add dl, '0'
.a4_s:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .a4_hex
    mov byte [rdi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 12
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print "D"
    mov rcx, [stdout_handle]
    lea rdx, [msg_d]
    mov r8d, 2
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; VirtualProtect on code buffer
    lea rcx, [code_buffer]
    mov edx, 2*1024*1024
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    ; Print "E"
    mov rcx, [stdout_handle]
    lea rdx, [msg_e]
    mov r8d, 2
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; Debug: print elf_buffer BEFORE CreateFileA
    mov byte [num_buf], 'B'
    mov byte [num_buf+1], 'C'
    mov byte [num_buf+2], ':'
    mov rax, [elf_buffer]
    lea rdi, [num_buf+3]
    mov ecx, 8
.bc_hex:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .bc_d
    add dl, 'A' - 10
    jmp .bc_s
.bc_d:
    add dl, '0'
.bc_s:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .bc_hex
    mov byte [rdi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 12
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

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
    je .file_error
    mov [file_handle], rax

    ; Debug: print elf_buffer AFTER CreateFileA (AC:)
    push rax
    mov byte [num_buf], 'A'
    mov byte [num_buf+1], 'C'
    mov byte [num_buf+2], ':'
    mov rax, [elf_buffer]
    lea rdi, [num_buf+3]
    mov ecx, 8
.ac_hex:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .ac_d
    add dl, 'A' - 10
    jmp .ac_s
.ac_d:
    add dl, '0'
.ac_s:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .ac_hex
    mov byte [rdi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 12
    lea r9, [write_count]
    mov qword [rsp+40], 0
    call WriteFile
    pop rax

    ; Print "F"
    mov rcx, [stdout_handle]
    lea rdx, [msg_f]
    mov r8d, 2
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; Read file
    mov rcx, [file_handle]
    mov rdx, [elf_buffer]
    mov r8d, 8*1024*1024
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call ReadFile

    ; Print ReadFile return value: "RF:X\n" (1=success, 0=fail)
    push rax
    mov byte [num_buf], 'R'
    mov byte [num_buf+1], 'F'
    mov byte [num_buf+2], ':'
    add al, '0'
    mov [num_buf+3], al
    mov byte [num_buf+4], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 5
    lea r9, [write_count]
    mov qword [rsp+40], 0
    call WriteFile
    pop rax

    ; Print bytes_read immediately: "RD:XXXXXXXX\n"
    mov byte [num_buf], 'R'
    mov byte [num_buf+1], 'D'
    mov byte [num_buf+2], ':'
    mov eax, [bytes_read]       ; ReadFile writes DWORD, not QWORD
    lea rdi, [num_buf+3]
    mov ecx, 8
.rd_hex_loop:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .rd_digit
    add dl, 'A' - 10
    jmp .rd_store
.rd_digit:
    add dl, '0'
.rd_store:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .rd_hex_loop
    mov byte [rdi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 12
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print elf_buffer address first
    mov byte [num_buf], 'E'
    mov byte [num_buf+1], 'B'
    mov byte [num_buf+2], ':'
    mov rax, [elf_buffer]
    lea rdi, [num_buf+3]
    mov ecx, 16
.eb_hex:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .eb_d
    add dl, 'A' - 10
    jmp .eb_s
.eb_d:
    add dl, '0'
.eb_s:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .eb_hex
    mov byte [rdi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 20
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print first 4 bytes of ELF buffer: "EF:XX XX XX XX\n"
    mov byte [num_buf], 'E'
    mov byte [num_buf+1], 'F'
    mov byte [num_buf+2], ':'
    mov rsi, [elf_buffer]
    mov ecx, 4
    lea rdi, [num_buf+3]
.ef_loop:
    movzx eax, byte [rsi]
    mov edx, eax
    shr edx, 4
    cmp dl, 10
    jb .ef_d1
    add dl, 'A' - 10
    jmp .ef_s1
.ef_d1:
    add dl, '0'
.ef_s1:
    mov [rdi], dl
    inc rdi
    and al, 0xF
    cmp al, 10
    jb .ef_d2
    add al, 'A' - 10
    jmp .ef_s2
.ef_d2:
    add al, '0'
.ef_s2:
    mov [rdi], al
    inc rdi
    mov byte [rdi], ' '
    inc rdi
    inc rsi
    dec ecx
    jnz .ef_loop
    mov byte [rdi-1], 10    ; Replace last space with newline
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 15
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print "G"
    mov rcx, [stdout_handle]
    lea rdx, [msg_g]
    mov r8d, 2
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; Close file
    mov rcx, [file_handle]
    call CloseHandle

    ; Init block cache
    call init_block_cache

    ; Print bytes_read before load_elf: "SZ:XXXXXXXX\n"
    mov byte [num_buf], 'S'
    mov byte [num_buf+1], 'Z'
    mov byte [num_buf+2], ':'
    mov rax, [bytes_read]
    lea rdi, [num_buf+3]
    mov ecx, 8
.sz_hex_loop:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .sz_digit
    add dl, 'A' - 10
    jmp .sz_store
.sz_digit:
    add dl, '0'
.sz_store:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .sz_hex_loop
    mov byte [rdi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 12
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; Load ELF
    mov rdi, [elf_buffer]
    mov rsi, [bytes_read]
    mov rdx, [guest_memory]
    mov rcx, 128*1024*1024
    call load_elf

    ; Print "H" and error code
    push rax
    mov rcx, [stdout_handle]
    lea rdx, [msg_h]
    mov r8d, 2
    lea r9, [write_count]
    mov qword [rsp+40], 0
    call WriteFile
    pop rax

    test eax, eax
    jnz .load_error

    ; Print elf_brk_base as "BRK:XXXXXXXX\n"
    mov byte [num_buf], 'B'
    mov byte [num_buf+1], 'R'
    mov byte [num_buf+2], 'K'
    mov byte [num_buf+3], ':'
    mov rax, [elf_brk_base]
    lea rdi, [num_buf+4]
    mov ecx, 8                  ; 8 hex digits
.brk_hex_loop:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .brk_digit
    add dl, 'A' - 10
    jmp .brk_store
.brk_digit:
    add dl, '0'
.brk_store:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .brk_hex_loop
    mov byte [rdi], 10          ; newline
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 13                 ; "BRK:XXXXXXXX\n"
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; Set up argv in guest memory
    mov rdi, [guest_memory]

    ; Copy "doom" to 0x6FE000
    lea rsi, [doom_str]
    mov rax, rdi
    add rax, 0x6FE000
    mov byte [rax], 'd'
    mov byte [rax+1], 'o'
    mov byte [rax+2], 'o'
    mov byte [rax+3], 'm'
    mov byte [rax+4], 0

    ; Copy "-iwad" to 0x6FE010
    mov rax, rdi
    add rax, 0x6FE010
    mov byte [rax], '-'
    mov byte [rax+1], 'i'
    mov byte [rax+2], 'w'
    mov byte [rax+3], 'a'
    mov byte [rax+4], 'd'
    mov byte [rax+5], 0

    ; Copy "doom1.wad" to 0x6FE020
    mov rax, rdi
    add rax, 0x6FE020
    mov byte [rax], 'd'
    mov byte [rax+1], 'o'
    mov byte [rax+2], 'o'
    mov byte [rax+3], 'm'
    mov byte [rax+4], '1'
    mov byte [rax+5], '.'
    mov byte [rax+6], 'w'
    mov byte [rax+7], 'a'
    mov byte [rax+8], 'd'
    mov byte [rax+9], 0

    ; Set up argv array at 0x700008
    mov qword [rdi + 0x700000], 3
    mov qword [rdi + 0x700008], 0x6FE000
    mov qword [rdi + 0x700010], 0x6FE010
    mov qword [rdi + 0x700018], 0x6FE020
    mov qword [rdi + 0x700020], 0

    ; Print "I"
    mov rcx, [stdout_handle]
    lea rdx, [msg_i]
    mov r8d, 2
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; Clear registers
    lea rax, [rv_regs]
    xor ecx, ecx
.clr:
    mov qword [rax + rcx*8], 0
    inc ecx
    cmp ecx, 32
    jb .clr

    ; Clear FP registers
    lea rax, [rv_fp_regs]
    xor ecx, ecx
.clr_fp:
    mov qword [rax + rcx*8], 0
    inc ecx
    cmp ecx, 32
    jb .clr_fp

    ; Print "J"
    mov rcx, [stdout_handle]
    lea rdx, [msg_j]
    mov r8d, 2
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; Set initial state
    mov qword [rv_regs + 2*8], 0x6FFFF0     ; sp
    mov qword [rv_regs + 10*8], 3           ; a0 = argc
    mov qword [rv_regs + 11*8], 0x700008    ; a1 = argv

    ; Print "K"
    mov rcx, [stdout_handle]
    lea rdx, [msg_k]
    mov r8d, 2
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    ; Execute
    call get_elf_entry_point
    mov [entry_point], rax

    ; Print "L" (got entry point)
    mov rcx, [stdout_handle]
    lea rdx, [msg_l]
    mov r8d, 2
    lea r9, [write_count]
    mov qword [rsp+32], 0
    call WriteFile

    mov eax, [entry_point]
    mov edi, eax
    mov rsi, [guest_memory]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    xor r8d, r8d
    lea r9, [rv_fp_regs]
    call execute_blocks

    ; Exit with a0
    mov ecx, [rv_regs + 10*8]
    call ExitProcess

.alloc_fail:
    mov ecx, 99
    call ExitProcess

.file_error:
    mov ecx, 100
    call ExitProcess

.load_error:
    mov ecx, 101
    call ExitProcess
