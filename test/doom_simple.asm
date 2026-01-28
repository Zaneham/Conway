; doom_simple.asm - Minimal Doom runner
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
extern GetStdHandle
extern WriteFile
extern stdout_handle
extern bytes_written
extern CreateFileA
extern ReadFile
extern CloseHandle

PAGE_EXECUTE_READWRITE  equ 0x40
MEM_COMMIT              equ 0x1000
MEM_RESERVE             equ 0x2000
STD_OUTPUT_HANDLE       equ -11

section .data
    msg_loading     db "Loading Doom...", 13, 10, 0
    msg_ok          db "ELF loaded, starting execution", 13, 10, 0
    msg_error       db "Error loading ELF", 13, 10, 0
    msg_1           db "1", 10
    msg_2           db "2", 10
    msg_3           db "3", 10
    msg_4           db "4", 10
    msg_5           db "5", 10
    msg_r1          db "R1", 10
    msg_r2          db "R2", 10
    doom_path       db "doomgeneric/doomgeneric/doom_conway.elf", 0
    doom_str        db "doom", 0
    iwad_str        db "-iwad", 0
    wad_str         db "doom1.wad", 0

section .bss
    alignb 8
    file_handle     resq 1
    bytes_read      resq 1
    chars_written   resq 1
    elf_buffer      resq 1
    guest_memory    resq 1
    rv_regs         resq 32
    rv_fp_regs      resq 32
    rv_pc           resq 1
    old_protect     resd 1

section .text
    global main

main:
    push rbp
    mov rbp, rsp
    sub rsp, 128

    ; Get stdout
    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [stdout_handle], rax

    ; Print loading message
    mov rcx, rax
    lea rdx, [msg_loading]
    mov r8d, 17
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Allocate 8MB for ELF buffer
    xor ecx, ecx
    mov edx, 8*1024*1024
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_EXECUTE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz .error
    mov [elf_buffer], rax

    ; Allocate 128MB for guest memory
    xor ecx, ecx
    mov edx, 128*1024*1024
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_EXECUTE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz .error
    mov [guest_memory], rax

    ; Debug: print "1"
    mov rcx, [stdout_handle]
    lea rdx, [msg_1]
    mov r8d, 2
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Read ELF file
    lea rcx, [doom_path]
    mov rdx, [elf_buffer]
    mov r8d, 8*1024*1024
    call read_file
    test eax, eax
    jz .error
    mov [bytes_read], rax

    ; Debug: print "2"
    mov rcx, [stdout_handle]
    lea rdx, [msg_2]
    mov r8d, 2
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; VirtualProtect on code buffer
    sub rsp, 8  ; alignment
    lea rcx, [code_buffer]
    mov edx, 2*1024*1024
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect
    add rsp, 8

    ; Init block cache
    call init_block_cache

    ; Load ELF
    mov rdi, [elf_buffer]
    mov rsi, [bytes_read]
    mov rdx, [guest_memory]
    mov rcx, 128*1024*1024
    call load_elf
    test eax, eax
    jnz .error

    ; Print OK message
    mov rcx, [stdout_handle]
    lea rdx, [msg_ok]
    mov r8d, 32
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Set up argv in guest memory
    ; "doom" at 0x6FE000, "-iwad" at 0x6FE010, "doom1.wad" at 0x6FE020
    mov rdi, [guest_memory]

    ; Copy strings
    lea rsi, [doom_str]
    lea rax, [rdi + 0x6FE000]
    mov rcx, 5
    rep movsb
    mov rdi, [guest_memory]

    lea rsi, [iwad_str]
    lea rax, [rdi + 0x6FE010]
    mov rdi, rax
    mov rcx, 6
    rep movsb
    mov rdi, [guest_memory]

    lea rsi, [wad_str]
    lea rax, [rdi + 0x6FE020]
    mov rdi, rax
    mov rcx, 10
    rep movsb
    mov rdi, [guest_memory]

    ; Set up argv array at 0x700008
    mov qword [rdi + 0x700000], 3            ; argc = 3
    mov qword [rdi + 0x700008], 0x6FE000     ; argv[0] = "doom"
    mov qword [rdi + 0x700010], 0x6FE010     ; argv[1] = "-iwad"
    mov qword [rdi + 0x700018], 0x6FE020     ; argv[2] = "doom1.wad"
    mov qword [rdi + 0x700020], 0            ; argv[3] = NULL

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
    lea rax, [rv_regs]
    mov rdi, [guest_memory]
    mov qword [rax + 2*8], 0x6FFFF0         ; sp = stack pointer (near top of lower 7MB)
    mov qword [rax + 10*8], 3               ; a0 = argc
    mov qword [rax + 11*8], 0x700008        ; a1 = &argv[0]

    ; Execute
    call elf_entry_point
    mov edi, eax                            ; Start PC
    mov rsi, [guest_memory]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    xor r8d, r8d                            ; 0 = unlimited blocks
    lea r9, [rv_fp_regs]
    call execute_blocks

    ; Get exit code from a0 (x10)
    mov ecx, [rv_regs + 10*8]
    jmp .exit

.error:
    mov rcx, [stdout_handle]
    lea rdx, [msg_error]
    mov r8d, 18
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile
    mov ecx, 1

.exit:
    call ExitProcess

; read_file(path, buffer, max_size) -> bytes read or 0 on error
read_file:
    push rbx
    push r12
    push r13
    sub rsp, 64

    ; Debug: print "R1"
    push rcx
    push rdx
    push r8
    sub rsp, 32         ; shadow space
    mov rcx, [stdout_handle]
    lea rdx, [msg_r1]
    mov r8d, 3
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 32
    pop r8
    pop rdx
    pop rcx

    mov r12, rdx        ; buffer
    mov r13, r8         ; max_size

    ; CreateFileA - rcx already has path
    mov edx, 0x80000000 ; GENERIC_READ
    mov r8d, 1          ; FILE_SHARE_READ
    xor r9d, r9d
    mov qword [rsp+32], 3   ; OPEN_EXISTING
    mov qword [rsp+40], 0x80 ; FILE_ATTRIBUTE_NORMAL
    mov qword [rsp+48], 0
    call CreateFileA

    ; Debug: print "R2" after CreateFileA
    push rax
    sub rsp, 40
    mov rcx, [stdout_handle]
    lea rdx, [msg_r2]
    mov r8d, 3
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 40
    pop rax

    cmp rax, -1
    je .read_fail
    mov rbx, rax        ; save handle

    ; ReadFile
    mov rcx, rbx
    mov rdx, r12
    mov r8, r13
    lea r9, [rsp+56]    ; bytes read
    mov qword [rsp+32], 0
    call ReadFile
    test eax, eax
    jz .read_close_fail

    mov rax, [rsp+56]   ; return bytes read

    ; CloseHandle
    push rax
    mov rcx, rbx
    call CloseHandle
    pop rax

    add rsp, 64
    pop r13
    pop r12
    pop rbx
    ret

.read_close_fail:
    mov rcx, rbx
    call CloseHandle
.read_fail:
    xor eax, eax
    add rsp, 64
    pop r13
    pop r12
    pop rbx
    ret
