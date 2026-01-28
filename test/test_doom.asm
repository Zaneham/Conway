; test_doom.asm - Load and attempt to execute Doom
; "It's happening!"
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
extern QueryPerformanceCounter
extern QueryPerformanceFrequency
extern Sleep

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

; Memory sizes
GUEST_MEM_SIZE          equ 8388608         ; 8MB guest memory
CODE_BUFFER_SIZE        equ 16777216        ; 16MB code buffer for translation
ELF_BUFFER_SIZE         equ 8388608         ; 8MB for ELF file

section .data
    elf_path        db "doomgeneric/doomgeneric/doom_conway.elf", 0
    msg_loading     db "Loading Doom...", 13, 10, 0
    msg_loaded      db "Doom loaded, entry point: ", 0
    msg_executing   db "Executing...", 13, 10, 0
    msg_failed      db "Failed to load Doom", 13, 10, 0
    msg_newline     db 13, 10, 0

section .bss
    old_protect     resd 1
    alignb 8
    file_handle     resq 1
    bytes_read      resq 1
    stdout_handle   resq 1
    chars_written   resq 1
    perf_freq       resq 1
    start_time      resq 1

    ; Pointers to allocated memory
    elf_buffer      resq 1
    guest_memory    resq 1

    ; RISC-V state
    rv_regs         resq 32
    rv_pc           resq 1

section .text
    global main

main:
    push rbp
    mov rbp, rsp
    sub rsp, 96                         ; 32 shadow + 56 for 7 args + 8 alignment

    ; Get stdout handle
    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [stdout_handle], rax

    ; Print start message
    mov rcx, rax
    lea rdx, [msg_loading]
    mov r8d, 17
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Get perf frequency
    lea rcx, [perf_freq]
    call QueryPerformanceFrequency

    ; Allocate ELF buffer
    xor ecx, ecx
    mov edx, ELF_BUFFER_SIZE
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz .fail
    mov [elf_buffer], rax

    ; Allocate guest memory (8MB)
    xor ecx, ecx
    mov edx, GUEST_MEM_SIZE
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz .fail_alloc_guest
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

    ; Print success
    mov rcx, [stdout_handle]
    lea rdx, [msg_loaded]
    mov r8d, 27
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; ELF loaded successfully - now set up execution

    ; Clear all RISC-V registers
    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 32
.clr_regs:
    mov [rdi + rcx*8 - 8], rax
    dec ecx
    jnz .clr_regs

    ; Set up stack pointer (sp = x2) at 0x700000 (near top of 8MB, grows down)
    ; Memory layout:
    ; 0x00010000-0x00200000: Code/data/BSS (~2MB)
    ; 0x00200000-0x00400000: Heap (~2MB)
    ; 0x00600000-0x00700000: Stack (1MB, grows down from 0x700000)
    ; 0x00700000-0x00800000: Framebuffer
    lea rax, [rv_regs]
    mov qword [rax + 2*8], 0x700000     ; sp = 0x700000

    ; Set up argc/argv in guest memory
    ; Put argv at 0x6FF000 (below stack), strings at 0x6FE000
    mov rdi, [guest_memory]

    ; argv[0] = "doom" at 0x6FE000
    mov byte [rdi + 0x6FE000], 'd'
    mov byte [rdi + 0x6FE001], 'o'
    mov byte [rdi + 0x6FE002], 'o'
    mov byte [rdi + 0x6FE003], 'm'
    mov byte [rdi + 0x6FE004], 0

    ; argv array at 0x6FF000:
    ; argv[0] = pointer to 0x6FE000
    ; argv[1] = NULL
    mov qword [rdi + 0x6FF000], 0x6FE000  ; argv[0] = "doom"
    mov qword [rdi + 0x6FF008], 0         ; argv[1] = NULL

    ; Set up registers
    lea rax, [rv_regs]
    mov qword [rax + 10*8], 1           ; a0 = argc = 1
    mov qword [rax + 11*8], 0x6FF000    ; a1 = argv

    ; Initialize break pointer for brk/mmap syscalls
    ; Store at guest_memory + 0xF000
    mov qword [rdi + 0xF000], 0x200000  ; Heap starts at 2MB

    ; Get entry point from ELF (virtual address)
    mov rdi, [elf_entry_point]

    ; Convert virtual address to guest memory offset
    ; ELF loads at vaddr 0x10000, but execute_blocks expects offset from code base
    ; The ELF's vaddr is the offset within guest memory
    ; So if entry is 0x10000, that's offset 0 from code at guest_memory + 0x10000

    ; execute_blocks(start_pc, code_base, rv_regs, pc_ptr, max_blocks)
    ; RDI = start PC (offset from code base)
    ; RSI = code base (guest_memory)
    ; RDX = rv_regs
    ; RCX = &rv_pc
    ; R8 = max blocks

    ; Entry point is virtual address (e.g., 0x104e0)
    ; Code base is guest_memory (ELF loads segments at their vaddrs)
    ; Start PC = entry_point directly

    ; Print "Starting..." message
    mov [rsp+56], rdi               ; Save rdi
    mov rcx, [stdout_handle]
    lea rdx, [msg_executing]
    mov r8d, 14
    lea r9, [chars_written]
    mov qword [rsp+32], 0
    call WriteFile
    mov rdi, [rsp+56]               ; Restore rdi

    mov rsi, [guest_memory]             ; Code base = guest_memory
    ; rdi already has entry_point (offset from base 0)

    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8d, 10000000                   ; Max blocks (10 million - Doom runs for a while!)

    call execute_blocks

    ; If we get here, execution ended (via exit syscall)
    ; Return value is in a0 (x10)
    lea rax, [rv_regs]
    mov ecx, [rax + 10*8]               ; Exit code from a0
    jmp .exit

.fail_alloc_guest:
    mov ecx, 200
    jmp .exit

.fail:
    mov ecx, 255

.exit:
    add rsp, 96
    pop rbp
    sub rsp, 40
    call ExitProcess
