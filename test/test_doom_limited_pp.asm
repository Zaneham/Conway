# 0 "test/test_doom_limited.asm"
# 0 "<built-in>"
# 0 "<command-line>"
# 1 "test/test_doom_limited.asm"
; test_doom_limited.asm - Run Doom with limited blocks to debug
bits 64
default rel

extern load_elf
extern elf_entry_point
extern init_block_cache
extern execute_blocks
extern code_buffer
extern debug_block_count
extern debug_last_pc
extern code_buf_ptr
extern ExitProcess
extern VirtualAlloc
extern VirtualProtect
extern CreateFileA
extern ReadFile
extern CloseHandle
extern GetStdHandle
extern WriteFile

PAGE_EXECUTE_READWRITE equ 0x40
PAGE_READWRITE equ 0x04
MEM_COMMIT equ 0x1000
MEM_RESERVE equ 0x2000
GENERIC_READ equ 0x80000000
FILE_SHARE_READ equ 1
OPEN_EXISTING equ 3
FILE_ATTRIBUTE_NORMAL equ 0x80
INVALID_HANDLE_VALUE equ -1
STD_OUTPUT_HANDLE equ -11

GUEST_MEM_SIZE equ 134217728
CODE_BUFFER_SIZE equ 16777216
ELF_BUFFER_SIZE equ 8388608
BLOCK_LIMIT equ 50000000

section .data
    elf_path db "doomgeneric/doomgeneric/doom_minimal.elf", 0
    msg_loading db "Loading Doom...", 13, 10, 0
    msg_done db "Done! Blocks: ", 0
    msg_pc db " PC: ", 0
    msg_buf db " Buf: ", 0
    msg_a0 db " a0: ", 0
    msg_gp db " gp: ", 0
    msg_a2 db " a2: ", 0
    msg_s10 db " s10: ", 0
    msg_nl db 13, 10, 0
    msg_elf_ok db "ELF OK", 13, 10, 0
    msg_exec_start db "EXEC", 13, 10, 0

section .bss
    old_protect resd 1
    alignb 8
    file_handle resq 1
    bytes_read resq 1
    stdout_handle resq 1
    bytes_written resq 1
    chars_written resq 1
    elf_buffer resq 1
    guest_memory resq 1
    rv_regs resq 32
    rv_pc resq 1
    num_buf resb 32

section .text
    global main
    global stdout_handle
    global bytes_written

main:
    push rbp
    mov rbp, rsp
    sub rsp, 96

    ; Get stdout
    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [stdout_handle], rax

    ; Print loading
    mov rcx, rax
    lea rdx, [msg_loading]
    mov r8d, 17
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Allocate ELF buffer
    xor ecx, ecx
    mov edx, ELF_BUFFER_SIZE
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz .fail
    mov [elf_buffer], rax

    ; Allocate guest memory
    xor ecx, ecx
    mov edx, GUEST_MEM_SIZE
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz .fail
    mov [guest_memory], rax

    ; Make code buffer executable
    lea rcx, [code_buffer]
    mov edx, CODE_BUFFER_SIZE
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    ; Init block cache
    call init_block_cache

    ; Open ELF file
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

    ; Read ELF file
    mov rcx, [file_handle]
    mov rdx, [elf_buffer]
    mov r8d, ELF_BUFFER_SIZE
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call ReadFile
    test eax, eax
    jz .fail

    ; Close file
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

    ; Debug: print "ELF OK\n"
    mov rcx, [stdout_handle]
    lea rdx, [msg_elf_ok]
    mov r8d, 7
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Debug: Check data section loaded - print value at guest 0x55400 (stdout.fd location)
    mov rdi, [guest_memory]
    mov eax, [rdi + 0x55400] ; Read what should be stdout.fd
    ; Print "D:XXXXXXXX\n"
    lea rdi, [num_buf]
    mov byte [rdi], 'D'
    mov byte [rdi+1], ':'
    ; Print as 8 hex digits
    mov ecx, 8
    lea rsi, [num_buf+9]
.data_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .data_digit
    add dl, 'A' - 10
    jmp .data_store
.data_digit:
    add dl, '0'
.data_store:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .data_hex
    mov byte [num_buf+10], 10 ; newline
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 11
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Debug: Print value at guest 0x58340 (the problem address)
    mov rdi, [guest_memory]
    mov rax, [rdi + 0x58340] ; Read 64-bit value
    ; Print "M:XXXXXXXXXXXXXXXX\n" (16 hex digits)
    lea rdi, [num_buf]
    mov byte [rdi], 'M'
    mov byte [rdi+1], ':'
    mov ecx, 16
    lea rsi, [num_buf+17]
.mem_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .mem_digit
    add dl, 'A' - 10
    jmp .mem_store
.mem_digit:
    add dl, '0'
.mem_store:
    mov [rsi], dl
    dec rsi
    shr rax, 4
    dec ecx
    jnz .mem_hex
    mov byte [num_buf+18], 10 ; newline
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 19
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Debug: print instruction at PC 0x109D4 (block 9250 - a0 load)
    mov rdi, [guest_memory]
    lea rsi, [num_buf]
    mov byte [rsi], 'R'
    mov byte [rsi+1], 'V'
    mov byte [rsi+2], '9'
    mov byte [rsi+3], 'D'
    mov byte [rsi+4], '4'
    mov byte [rsi+5], ':'
    add rsi, 6
    ; Dump 32 bytes starting at 0x109D4
    lea rdi, [rdi + 0x109D4]
    mov ecx, 32
.rv9d4_loop:
    push rcx
    push rdi
    movzx eax, byte [rdi]
    mov edx, eax
    shr edx, 4
    cmp dl, 10
    jb .rv9d4_d1
    add dl, 'A' - 10
    jmp .rv9d4_s1
.rv9d4_d1:
    add dl, '0'
.rv9d4_s1:
    mov [rsi], dl
    inc rsi
    and eax, 0xF
    cmp al, 10
    jb .rv9d4_d2
    add al, 'A' - 10
    jmp .rv9d4_s2
.rv9d4_d2:
    add al, '0'
.rv9d4_s2:
    mov [rsi], al
    inc rsi
    pop rdi
    pop rcx
    inc rdi
    dec ecx
    jnz .rv9d4_loop
    mov byte [rsi], 10
    inc rsi
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8, rsi
    sub r8, rdx
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Debug: print instruction at PC 0x10826 (block 9252 - s4 corruption)
    mov rdi, [guest_memory]
    lea rsi, [num_buf]
    mov byte [rsi], 'R'
    mov byte [rsi+1], 'V'
    mov byte [rsi+2], '8'
    mov byte [rsi+3], '2'
    mov byte [rsi+4], '6'
    mov byte [rsi+5], ':'
    add rsi, 6
    ; Dump 32 bytes starting at 0x10826
    lea rdi, [rdi + 0x10826]
    mov ecx, 32
.rv826_loop:
    push rcx
    push rdi
    movzx eax, byte [rdi]
    ; Convert to 2 hex digits
    mov edx, eax
    shr edx, 4
    cmp dl, 10
    jb .rv826_d1
    add dl, 'A' - 10
    jmp .rv826_s1
.rv826_d1:
    add dl, '0'
.rv826_s1:
    mov [rsi], dl
    inc rsi
    and eax, 0xF
    cmp al, 10
    jb .rv826_d2
    add al, 'A' - 10
    jmp .rv826_s2
.rv826_d2:
    add al, '0'
.rv826_s2:
    mov [rsi], al
    inc rsi
    pop rdi
    pop rcx
    inc rdi
    dec ecx
    jnz .rv826_loop
    mov byte [rsi], 10
    inc rsi
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8, rsi
    sub r8, rdx
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile
    jmp .done_instr_print

.put_hex:
    ; Print eax as 8 hex digits to [rsi], advance rsi by 8
    push rbx
    mov ecx, 8
.ph_loop:
    rol eax, 4
    mov ebx, eax
    and ebx, 0xF
    cmp bl, 10
    jb .ph_digit
    add bl, 'A' - 10
    jmp .ph_store
.ph_digit:
    add bl, '0'
.ph_store:
    mov [rsi], bl
    inc rsi
    dec ecx
    jnz .ph_loop
    pop rbx
    ret

.done_instr_print:

    ; Clear RISC-V registers
    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 32
.clr_regs:
    mov [rdi + rcx*8 - 8], rax
    dec ecx
    jnz .clr_regs

    ; ===== MINIMAL STACK SETUP FOR crt0_minimal.S =====
    mov rdi, [guest_memory]

    ; "doom" string at 0x6FE000
    mov byte [rdi + 0x6FE000], 'd'
    mov byte [rdi + 0x6FE001], 'o'
    mov byte [rdi + 0x6FE002], 'o'
    mov byte [rdi + 0x6FE003], 'm'
    mov byte [rdi + 0x6FE004], 0

    ; "-iwad" at 0x6FE010
    mov byte [rdi + 0x6FE010], '-'
    mov byte [rdi + 0x6FE011], 'i'
    mov byte [rdi + 0x6FE012], 'w'
    mov byte [rdi + 0x6FE013], 'a'
    mov byte [rdi + 0x6FE014], 'd'
    mov byte [rdi + 0x6FE015], 0

    ; "doom1.wad" at 0x6FE020
    mov byte [rdi + 0x6FE020], 'd'
    mov byte [rdi + 0x6FE021], 'o'
    mov byte [rdi + 0x6FE022], 'o'
    mov byte [rdi + 0x6FE023], 'm'
    mov byte [rdi + 0x6FE024], '1'
    mov byte [rdi + 0x6FE025], '.'
    mov byte [rdi + 0x6FE026], 'w'
    mov byte [rdi + 0x6FE027], 'a'
    mov byte [rdi + 0x6FE028], 'd'
    mov byte [rdi + 0x6FE029], 0

    ; Stack data at 0x700000 (sp points here)
    ; Minimal Linux ABI: argc at [sp], argv array at [sp+8]
    ; Stack layout for minimal crt0:
    ; sp+0: argc
    ; sp+8: argv[0]
    ; sp+16: argv[1]
    ; sp+24: argv[2]
    ; sp+32: NULL (end of argv)
    ; sp+40: NULL (end of envp)
    mov qword [rdi + 0x700000], 3 ; argc = 3
    mov qword [rdi + 0x700008], 0x6FE000 ; argv[0] = "doom"
    mov qword [rdi + 0x700010], 0x6FE010 ; argv[1] = "-iwad"
    mov qword [rdi + 0x700018], 0x6FE020 ; argv[2] = "doom1.wad"
    mov qword [rdi + 0x700020], 0 ; argv[3] = NULL (end of argv)
    mov qword [rdi + 0x700028], 0 ; envp[0] = NULL (empty environment)

    ; Set up registers
    lea rax, [rv_regs]
    mov rcx, 0xDEAD0000 ; Use register for large immediate
    mov [rax + 1*8], rcx ; ra = magic exit address
    mov qword [rax + 2*8], 0x700000 ; sp = stack pointer
    ; gp = 0 (let _start initialize it via AUIPC)
    mov qword [rax + 3*8], 0
    mov qword [rax + 4*8], 0 ; tp = 0 (let glibc initialize TLS)
    mov qword [rax + 10*8], 1 ; a0 = argc
    mov qword [rax + 11*8], 0x700008 ; a1 = &argv[0]

    ; Set up minimal TLS area at 0x600000
    ; TCB (Thread Control Block) is at tp
    ; pthread_self and errno typically use tp-relative offsets
    mov qword [rdi + 0x600000], 0 ; Clear TLS area

    ; Initialize break pointer
    mov qword [rdi + 0xF000], 0x200000

    ; Debug: print "EXEC\n" before starting execution
    mov rcx, [stdout_handle]
    lea rdx, [msg_exec_start]
    mov r8d, 6
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Execute with limited blocks
    mov rdi, [elf_entry_point]
    mov rsi, [guest_memory]
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8d, BLOCK_LIMIT
    call execute_blocks

    ; Print results
    mov rcx, [stdout_handle]
    lea rdx, [msg_done]
    mov r8d, 14
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print block count
    mov rax, [debug_block_count]
    lea rdi, [num_buf]
    call .print_hex
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 8
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print PC label
    mov rcx, [stdout_handle]
    lea rdx, [msg_pc]
    mov r8d, 5
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print last PC
    mov rax, [debug_last_pc]
    lea rdi, [num_buf]
    call .print_hex
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 8
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print buffer label
    mov rcx, [stdout_handle]
    lea rdx, [msg_buf]
    mov r8d, 6
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print code buffer usage
    mov rax, [code_buf_ptr]
    lea rcx, [code_buffer]
    sub rax, rcx
    lea rdi, [num_buf]
    call .print_hex
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 8
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print a0 label
    mov rcx, [stdout_handle]
    lea rdx, [msg_a0]
    mov r8d, 5
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print a0 value
    lea rax, [rv_regs]
    mov rax, [rax + 10*8]
    lea rdi, [num_buf]
    call .print_hex
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 8
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print gp label
    mov rcx, [stdout_handle]
    lea rdx, [msg_gp]
    mov r8d, 5
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print gp value (x3)
    lea rax, [rv_regs]
    mov rax, [rax + 3*8]
    lea rdi, [num_buf]
    call .print_hex
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 8
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print a2 (x12)
    mov rcx, [stdout_handle]
    lea rdx, [msg_a2]
    mov r8d, 5
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    lea rax, [rv_regs]
    mov rax, [rax + 12*8]
    lea rdi, [num_buf]
    call .print_hex
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 8
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print s10 (x26)
    mov rcx, [stdout_handle]
    lea rdx, [msg_s10]
    mov r8d, 6
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    lea rax, [rv_regs]
    mov rax, [rax + 26*8]
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

    mov ecx, 0
    jmp .exit

.fail:
    mov ecx, 255

.exit:
    add rsp, 96
    pop rbp
    sub rsp, 40
    call ExitProcess

; Print 32-bit hex value in RAX to [RDI]
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
