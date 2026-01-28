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
; Debug symbols removed - not needed for basic execution
; extern doom_lbu_addr
; extern doom_lbu_val
; extern doom_lbu_captured
; extern doom_lw_addr
; extern doom_lw_val
; extern doom_lw_captured
; extern sb_c_addr
; extern sb_c_captured
; extern sb_target_val
; extern sb_target_captured
; extern sw_corrupt_addr
; extern sw_corrupt_stored
; extern sw_corrupt_readback
; extern sw_corrupt_captured
extern ExitProcess
extern VirtualAlloc
extern VirtualProtect
extern CreateFileA
extern ReadFile
extern CloseHandle
extern GetStdHandle
extern WriteFile
extern stdout_handle
extern bytes_written

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

GUEST_MEM_SIZE          equ 134217728
CODE_BUFFER_SIZE        equ 16777216
ELF_BUFFER_SIZE         equ 8388608
BLOCK_LIMIT             equ 50000000

section .data
    elf_path        db "doomgeneric/doomgeneric/doom_minimal.elf", 0
    msg_loading     db "Loading Doom...", 13, 10, 0
    msg_done        db "Done! Blocks: ", 0
    msg_pc          db " PC: ", 0
    msg_buf         db " Buf: ", 0
    msg_a0          db " a0: ", 0
    msg_gp          db " gp: ", 0
    msg_a2          db " a2: ", 0
    msg_s10         db " s10: ", 0
    msg_nl          db 13, 10, 0
    msg_elf_ok      db "ELF OK", 13, 10, 0
    msg_exec_start  db "EXEC", 13, 10, 0
    msg_swc         db "SWC:", 0                ; SW Corruption prefix
    msg_swc_no      db "SWC:no", 13, 10, 0      ; No SW corruption
    msg_sep         db "/", 0

section .bss
    old_protect     resd 1
    alignb 8
    file_handle     resq 1
    bytes_read      resq 1
    chars_written   resq 1
    elf_buffer      resq 1
    guest_memory    resq 1
    rv_regs         resq 32
    rv_pc           resq 1
    num_buf         resb 32

section .text
    global main

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
    mov eax, [rdi + 0x55400]        ; Read what should be stdout.fd
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
    mov byte [num_buf+10], 10       ; newline
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 11
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Debug: Print first 10 bytes at guest 0x6FE020 (argv "doom1.wad")
    ; This is where the string "doom1.wad" is set up in test argv
    mov rdi, [guest_memory]
    add rdi, 0x6FE020
    ; Print "RO:" then 10 bytes as ASCII
    lea rsi, [num_buf]
    mov byte [rsi], 'R'
    mov byte [rsi+1], 'O'
    mov byte [rsi+2], ':'
    add rsi, 3              ; point to position for first char
    mov ecx, 10
.ro_loop:
    movzx eax, byte [rdi]
    mov [rsi], al
    inc rsi
    inc rdi
    dec ecx
    jnz .ro_loop
    mov byte [num_buf+13], 10       ; newline
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 14
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Debug: Print 16 bytes BEFORE 0x3ae18 as hex to see context
    ; Print "B4:" then 16 hex bytes
    mov rdi, [guest_memory]
    add rdi, 0x3ae08                ; 16 bytes before 0x3ae18
    lea rsi, [num_buf]
    mov byte [rsi], 'B'
    mov byte [rsi+1], '4'
    mov byte [rsi+2], ':'
    add rsi, 3
    mov ecx, 16
.b4_loop:
    push rcx
    push rdi
    movzx eax, byte [rdi]
    ; Convert to 2 hex digits
    mov edx, eax
    shr edx, 4
    cmp dl, 10
    jb .b4_d1
    add dl, 'A' - 10
    jmp .b4_s1
.b4_d1:
    add dl, '0'
.b4_s1:
    mov [rsi], dl
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .b4_d2
    add dl, 'A' - 10
    jmp .b4_s2
.b4_d2:
    add dl, '0'
.b4_s2:
    mov [rsi+1], dl
    add rsi, 2
    pop rdi
    inc rdi
    pop rcx
    dec ecx
    jnz .b4_loop
    mov byte [rsi], 10              ; newline
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 36                     ; "B4:" + 32 hex chars + newline
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Debug: Print value at guest 0x58340 (the problem address)
    mov rdi, [guest_memory]
    mov rax, [rdi + 0x58340]        ; Read 64-bit value
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
    mov byte [num_buf+18], 10       ; newline
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
    ; sp+0:   argc
    ; sp+8:   argv[0]
    ; sp+16:  argv[1]
    ; sp+24:  argv[2]
    ; sp+32:  NULL (end of argv)
    ; sp+40:  NULL (end of envp)
    mov qword [rdi + 0x700000], 3           ; argc = 3
    mov qword [rdi + 0x700008], 0x6FE000    ; argv[0] = "doom"
    mov qword [rdi + 0x700010], 0x6FE010    ; argv[1] = "-iwad"
    mov qword [rdi + 0x700018], 0x6FE020    ; argv[2] = "doom1.wad"
    mov qword [rdi + 0x700020], 0           ; argv[3] = NULL (end of argv)
    mov qword [rdi + 0x700028], 0           ; envp[0] = NULL (empty environment)

    ; DEBUG: Verify "doom1.wad" is set up at 0x6FE020
    ; Print "TS:" (Test Setup) then first 3 chars of the string
    ; Save rdi before calling WriteFile
    mov [rbp-8], rdi            ; save guest_memory ptr
    lea rsi, [num_buf]
    mov byte [rsi], 'T'
    mov byte [rsi+1], 'S'
    mov byte [rsi+2], ':'
    mov rax, [guest_memory]
    add rax, 0x6FE020
    movzx edx, byte [rax]       ; First char
    mov byte [rsi+3], dl
    movzx edx, byte [rax+1]     ; Second char
    mov byte [rsi+4], dl
    movzx edx, byte [rax+2]     ; Third char
    mov byte [rsi+5], dl
    mov byte [rsi+6], 10        ; newline
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 7
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile
    mov rdi, [rbp-8]            ; restore guest_memory ptr

    ; Also print first char via argv[2] ptr "TR:" (Test Register)
    mov rax, [rdi + 0x700018]   ; Load argv[2] pointer (should be 0x6FE020)
    lea rsi, [num_buf]
    mov byte [rsi], 'T'
    mov byte [rsi+1], 'R'
    mov byte [rsi+2], ':'
    ; Print first char at that guest address
    add rax, rdi                ; host address = guest_memory + guest_ptr
    movzx eax, byte [rax]       ; Read first char
    mov byte [rsi+3], al
    mov byte [rsi+4], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 5
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile
    mov rdi, [rbp-8]            ; restore guest_memory ptr again

    ; Set up registers
    lea rax, [rv_regs]
    mov rcx, 0xDEAD0000                     ; Use register for large immediate
    mov [rax + 1*8], rcx                    ; ra = magic exit address
    mov qword [rax + 2*8], 0x700000         ; sp = stack pointer
    ; gp = 0 (let _start initialize it via AUIPC)
    mov qword [rax + 3*8], 0
    mov qword [rax + 4*8], 0                ; tp = 0 (let glibc initialize TLS)
    mov qword [rax + 10*8], 1               ; a0 = argc
    mov qword [rax + 11*8], 0x700008        ; a1 = &argv[0]

    ; Set up minimal TLS area at 0x600000
    ; TCB (Thread Control Block) is at tp
    ; pthread_self and errno typically use tp-relative offsets
    mov qword [rdi + 0x600000], 0           ; Clear TLS area

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

    ; Print doom_lbu info if captured: "DL:XXXXXXXX V:XX C:X\n"
    cmp byte [doom_lbu_captured], 0
    je .skip_doom_lbu

    ; Print "DL:"
    lea rsi, [num_buf]
    mov byte [rsi], 'D'
    mov byte [rsi+1], 'L'
    mov byte [rsi+2], ':'
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 3
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print doom_lbu_addr (8 hex digits)
    mov rax, [doom_lbu_addr]
    lea rdi, [num_buf]
    call .print_hex
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 8
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print " V:"
    lea rsi, [num_buf]
    mov byte [rsi], ' '
    mov byte [rsi+1], 'V'
    mov byte [rsi+2], ':'
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 3
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print doom_lbu_val (2 hex digits)
    movzx eax, byte [doom_lbu_val]
    lea rdi, [num_buf]
    ; Print 2 hex digits manually
    mov edx, eax
    shr edx, 4
    cmp dl, 10
    jb .dl_digit1
    add dl, 'A' - 10
    jmp .dl_store1
.dl_digit1:
    add dl, '0'
.dl_store1:
    mov [rdi], dl
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .dl_digit2
    add dl, 'A' - 10
    jmp .dl_store2
.dl_digit2:
    add dl, '0'
.dl_store2:
    mov [rdi+1], dl

    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 2
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print " C:" and the ASCII char
    lea rsi, [num_buf]
    mov byte [rsi], ' '
    mov byte [rsi+1], 'C'
    mov byte [rsi+2], ':'
    movzx eax, byte [doom_lbu_val]
    mov [rsi+3], al
    mov byte [rsi+4], 10        ; newline
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 5
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile
    jmp .after_doom_lbu

.skip_doom_lbu:
    ; Print "DL:nocap\n" if not captured
    lea rsi, [num_buf]
    mov byte [rsi], 'D'
    mov byte [rsi+1], 'L'
    mov byte [rsi+2], ':'
    mov byte [rsi+3], 'n'
    mov byte [rsi+4], 'o'
    mov byte [rsi+5], 'c'
    mov byte [rsi+6], 'a'
    mov byte [rsi+7], 'p'
    mov byte [rsi+8], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 9
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

.after_doom_lbu:

    ; Print doom_lw info if captured: "LW:XXXXXXXX V:XXXXXXXX\n"
    cmp byte [doom_lw_captured], 0
    je .skip_doom_lw

    ; Print "LW:"
    lea rsi, [num_buf]
    mov byte [rsi], 'L'
    mov byte [rsi+1], 'W'
    mov byte [rsi+2], ':'
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 3
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print doom_lw_addr (8 hex digits)
    mov rax, [doom_lw_addr]
    lea rdi, [num_buf]
    call .print_hex
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 8
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print " V:"
    lea rsi, [num_buf]
    mov byte [rsi], ' '
    mov byte [rsi+1], 'V'
    mov byte [rsi+2], ':'
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 3
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print doom_lw_val (8 hex digits)
    mov eax, [doom_lw_val]
    lea rdi, [num_buf]
    call .print_hex
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 8
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print newline
    mov rcx, [stdout_handle]
    lea rdx, [msg_nl]
    mov r8d, 2
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile
    jmp .after_doom_lw

.skip_doom_lw:
    ; Print "LW:nocap\n" if not captured
    lea rsi, [num_buf]
    mov byte [rsi], 'L'
    mov byte [rsi+1], 'W'
    mov byte [rsi+2], ':'
    mov byte [rsi+3], 'n'
    mov byte [rsi+4], 'o'
    mov byte [rsi+5], 'c'
    mov byte [rsi+6], 'a'
    mov byte [rsi+7], 'p'
    mov byte [rsi+8], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 9
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

.after_doom_lw:

    ; Print sb_c info if captured: "SC:XXXXXXXX\n"
    cmp byte [sb_c_captured], 0
    je .skip_sb_c

    ; Print "SC:"
    lea rsi, [num_buf]
    mov byte [rsi], 'S'
    mov byte [rsi+1], 'C'
    mov byte [rsi+2], ':'
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 3
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print sb_c_addr (8 hex digits)
    mov rax, [sb_c_addr]
    lea rdi, [num_buf]
    call .print_hex
    mov byte [num_buf+8], 10        ; newline
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 9
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile
    jmp .after_sb_c

.skip_sb_c:
    ; Print "SC:nocap\n"
    lea rsi, [num_buf]
    mov byte [rsi], 'S'
    mov byte [rsi+1], 'C'
    mov byte [rsi+2], ':'
    mov byte [rsi+3], 'n'
    mov byte [rsi+4], 'o'
    mov byte [rsi+5], 'c'
    mov byte [rsi+6], 'a'
    mov byte [rsi+7], 'p'
    mov byte [rsi+8], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 9
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

.after_sb_c:

    ; Print sb_target info: "ST:XX\n" (what was stored at 0x6FFA4F)
    cmp byte [sb_target_captured], 0
    je .skip_sb_target

    ; Print "ST:" then value
    lea rsi, [num_buf]
    mov byte [rsi], 'S'
    mov byte [rsi+1], 'T'
    mov byte [rsi+2], ':'
    movzx eax, byte [sb_target_val]
    ; Convert to 2 hex digits
    mov edx, eax
    shr edx, 4
    cmp dl, 10
    jb .st_d1
    add dl, 'A' - 10
    jmp .st_s1
.st_d1:
    add dl, '0'
.st_s1:
    mov [rsi+3], dl
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .st_d2
    add dl, 'A' - 10
    jmp .st_s2
.st_d2:
    add dl, '0'
.st_s2:
    mov [rsi+4], dl
    mov byte [rsi+5], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 6
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile
    jmp .after_st

.skip_sb_target:
    lea rsi, [num_buf]
    mov byte [rsi], 'S'
    mov byte [rsi+1], 'T'
    mov byte [rsi+2], ':'
    mov byte [rsi+3], 'n'
    mov byte [rsi+4], 'o'
    mov byte [rsi+5], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8d, 6
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

.after_st:

    ; Print SW corruption info
    cmp byte [sw_corrupt_captured], 0
    je .skip_sw_corrupt

    ; Print "SWC:ADDR/STORED/READBACK\n"
    lea rsi, [num_buf]
    mov byte [rsi], 'S'
    mov byte [rsi+1], 'W'
    mov byte [rsi+2], 'C'
    mov byte [rsi+3], ':'
    add rsi, 4
    mov rdi, rsi
    mov rax, [sw_corrupt_addr]
    call .print_hex
    mov byte [rdi], '/'
    inc rdi
    mov eax, [sw_corrupt_stored]
    call .print_hex
    mov byte [rdi], '/'
    inc rdi
    mov eax, [sw_corrupt_readback]
    call .print_hex
    mov byte [rdi], 10
    inc rdi
    ; Write it
    mov rcx, [stdout_handle]
    lea rdx, [num_buf]
    mov r8, rdi
    sub r8, rdx
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile
    jmp .after_swc

.skip_sw_corrupt:
    ; Print "SWC:no\n"
    mov rcx, [stdout_handle]
    lea rdx, [msg_swc_no]
    mov r8d, 8
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

.after_swc:

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
