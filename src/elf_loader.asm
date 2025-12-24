; elf_loader.asm - ELF64 RISC-V Binary Loader
; "One does not simply walk into Mordor, but one can parse an ELF header"
;
; Parses ELF64 binaries and loads them into guest memory for execution.
; Supports RISC-V (EM_RISCV = 0xF3) little-endian 64-bit executables.

bits 64
default rel

;==============================================================================
; ELF Constants - The Magic Numbers of the Ancients
;==============================================================================

; ELF Magic - 0x7F followed by 'ELF' in ASCII
; If it doesn't start with this, it's not an ELF. Probably a confused JPEG.
ELF_MAGIC           equ 0x464C457F      ; Little-endian: 0x7F 'E' 'L' 'F'

; ELF Class
ELFCLASS64          equ 2               ; 64-bit objects

; ELF Data Encoding
ELFDATA2LSB         equ 1               ; Little-endian (the correct way)

; ELF Machine Types
EM_RISCV            equ 0xF3            ; RISC-V (243 in decimal)

; ELF Types
ET_EXEC             equ 2               ; Executable file

; Programme Header Types
PT_NULL             equ 0               ; Unused entry (bit of a waste really)
PT_LOAD             equ 1               ; Loadable segment (the interesting bit)

; ELF64 Header Offsets - Where to find the good stuff
ELF_E_IDENT         equ 0               ; 16 bytes of identification
ELF_E_TYPE          equ 16              ; Object file type
ELF_E_MACHINE       equ 18              ; Architecture
ELF_E_VERSION       equ 20              ; Object file version
ELF_E_ENTRY         equ 24              ; Entry point virtual address
ELF_E_PHOFF         equ 32              ; Programme header table offset
ELF_E_SHOFF         equ 40              ; Section header table offset
ELF_E_FLAGS         equ 48              ; Processor-specific flags
ELF_E_EHSIZE        equ 52              ; ELF header size
ELF_E_PHENTSIZE     equ 54              ; Programme header entry size
ELF_E_PHNUM         equ 56              ; Programme header entry count
ELF_E_SHENTSIZE     equ 58              ; Section header entry size
ELF_E_SHNUM         equ 60              ; Section header entry count
ELF_E_SHSTRNDX      equ 62              ; Section header string table index

; ELF64 Programme Header Offsets
PHDR_P_TYPE         equ 0               ; Segment type
PHDR_P_FLAGS        equ 4               ; Segment flags
PHDR_P_OFFSET       equ 8               ; Segment file offset
PHDR_P_VADDR        equ 16              ; Segment virtual address
PHDR_P_PADDR        equ 24              ; Segment physical address
PHDR_P_FILESZ       equ 32              ; Segment size in file
PHDR_P_MEMSZ        equ 40              ; Segment size in memory
PHDR_P_ALIGN        equ 48              ; Segment alignment

; Sizes
ELF64_HEADER_SIZE   equ 64              ; Size of ELF64 header
ELF64_PHDR_SIZE     equ 56              ; Size of programme header entry

; Error codes - For when things go pear-shaped
ELF_OK              equ 0               ; All tickety-boo
ELF_ERR_NOT_ELF     equ 1               ; Not an ELF file (impostor!)
ELF_ERR_NOT_64BIT   equ 2               ; 32-bit? In this economy?
ELF_ERR_NOT_LE      equ 3               ; Big-endian (the wrong way)
ELF_ERR_NOT_RISCV   equ 4               ; Wrong architecture, mate
ELF_ERR_NOT_EXEC    equ 5               ; Not executable (perhaps a library having an identity crisis)
ELF_ERR_NO_SEGMENTS equ 6               ; No loadable segments (empty inside, like my coffee cup)
ELF_ERR_TOO_BIG     equ 7               ; Won't fit in guest memory (greedy)

section .data
    ; Guest memory size - 64KB ought to be enough for anybody
    ; (Apologies to Mr Gates)
    guest_mem_size  dq 65536

section .bss
    ; ELF info structure - filled in by load_elf
    alignb 8
    elf_entry_point resq 1              ; Entry point address
    elf_load_base   resq 1              ; Base address where we loaded it

section .text
    global load_elf
    global validate_elf_header
    global elf_entry_point
    global elf_load_base

;==============================================================================
; validate_elf_header
; Checks if a buffer contains a valid RISC-V ELF64 executable header
;
; Input:  RDI = pointer to buffer containing ELF header (at least 64 bytes)
; Output: RAX = 0 if valid, error code otherwise
;
; "Trust, but verify" - Ronald Reagan (on ELF headers)
;==============================================================================
validate_elf_header:
    push rbx

    ; Check magic number (0x7F 'E' 'L' 'F')
    mov eax, [rdi]
    cmp eax, ELF_MAGIC
    jne .not_elf

    ; Check class (must be 64-bit)
    mov al, [rdi + 4]
    cmp al, ELFCLASS64
    jne .not_64bit

    ; Check endianness (must be little-endian)
    mov al, [rdi + 5]
    cmp al, ELFDATA2LSB
    jne .not_le

    ; Check machine type (must be RISC-V)
    movzx eax, word [rdi + ELF_E_MACHINE]
    cmp ax, EM_RISCV
    jne .not_riscv

    ; Check type (should be executable)
    movzx eax, word [rdi + ELF_E_TYPE]
    cmp ax, ET_EXEC
    jne .not_exec

    ; All checks passed - it's a proper ELF, not some riff-raff
    xor eax, eax
    jmp .done

.not_elf:
    mov eax, ELF_ERR_NOT_ELF
    jmp .done

.not_64bit:
    mov eax, ELF_ERR_NOT_64BIT
    jmp .done

.not_le:
    mov eax, ELF_ERR_NOT_LE
    jmp .done

.not_riscv:
    mov eax, ELF_ERR_NOT_RISCV
    jmp .done

.not_exec:
    mov eax, ELF_ERR_NOT_EXEC

.done:
    pop rbx
    ret

;==============================================================================
; load_elf
; Loads an ELF64 RISC-V executable into guest memory
;
; Input:  RDI = pointer to ELF file in memory
;         RSI = size of ELF file
;         RDX = pointer to guest memory buffer
;         RCX = size of guest memory buffer
; Output: RAX = 0 on success, error code on failure
;         On success:
;           [elf_entry_point] = entry point address
;           [elf_load_base] = base address in guest memory
;
; "Loading... please wait" - Every computer ever
;==============================================================================
load_elf:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Save parameters
    mov [rbp-8], rdi            ; ELF file pointer
    mov [rbp-16], rsi           ; ELF file size
    mov [rbp-24], rdx           ; Guest memory pointer
    mov [rbp-32], rcx           ; Guest memory size

    ; First, validate the header
    call validate_elf_header
    test eax, eax
    jnz .error                  ; Validation failed

    ; Get entry point
    mov rdi, [rbp-8]
    mov rax, [rdi + ELF_E_ENTRY]
    mov [elf_entry_point], rax

    ; Get programme header info
    mov rax, [rdi + ELF_E_PHOFF]    ; Programme header offset
    mov [rbp-40], rax
    movzx r12, word [rdi + ELF_E_PHNUM]  ; Number of programme headers

    ; Check we have at least one programme header
    test r12, r12
    jz .no_segments

    ; R13 = pointer to first programme header
    mov r13, [rbp-8]
    add r13, [rbp-40]

    ; R14 = guest memory base
    mov r14, [rbp-24]

    ; R15 = guest memory size
    mov r15, [rbp-32]

    ; Track lowest virtual address for load base
    mov qword [elf_load_base], 0xFFFFFFFFFFFFFFFF

    ; Iterate through programme headers
    xor ebx, ebx                ; EBX = counter

.load_loop:
    cmp ebx, r12d
    jge .load_done

    ; Check if this is a PT_LOAD segment
    mov eax, [r13 + PHDR_P_TYPE]
    cmp eax, PT_LOAD
    jne .next_header

    ; Get segment info
    mov rax, [r13 + PHDR_P_VADDR]   ; Virtual address
    mov rcx, [r13 + PHDR_P_FILESZ]  ; File size
    mov rdx, [r13 + PHDR_P_MEMSZ]   ; Memory size
    mov rsi, [r13 + PHDR_P_OFFSET]  ; File offset

    ; Update load base if this is lower
    cmp rax, [elf_load_base]
    jae .skip_base_update
    mov [elf_load_base], rax
.skip_base_update:

    ; Check if segment fits in guest memory
    ; For simplicity, we load at vaddr directly (assuming small addresses)
    ; A proper loader would handle relocation, but we're not barbarians... actually, we are
    add rax, rdx                ; vaddr + memsz
    cmp rax, r15                ; Compare with guest memory size
    ja .too_big

    ; Copy segment from file to guest memory
    ; Destination: guest_mem + vaddr
    mov rdi, r14                ; Guest memory base
    add rdi, [r13 + PHDR_P_VADDR]   ; + virtual address

    ; Source: elf_file + offset
    mov rsi, [rbp-8]            ; ELF file base
    add rsi, [r13 + PHDR_P_OFFSET]  ; + file offset

    ; Count: filesz bytes
    mov rcx, [r13 + PHDR_P_FILESZ]

    ; Copy the bytes (like a diligent photocopier)
    test rcx, rcx
    jz .zero_fill               ; Nothing to copy from file

    ; Manual copy loop (rep movsb would be faster but this is clearer)
.copy_loop:
    test rcx, rcx
    jz .zero_fill
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jmp .copy_loop

.zero_fill:
    ; Zero-fill the rest if memsz > filesz (for .bss and friends)
    mov rcx, [r13 + PHDR_P_MEMSZ]
    sub rcx, [r13 + PHDR_P_FILESZ]
    test rcx, rcx
    jz .next_header

.zero_loop:
    test rcx, rcx
    jz .next_header
    mov byte [rdi], 0
    inc rdi
    dec rcx
    jmp .zero_loop

.next_header:
    ; Move to next programme header
    add r13, ELF64_PHDR_SIZE
    inc ebx
    jmp .load_loop

.load_done:
    ; Success!
    xor eax, eax
    jmp .cleanup

.no_segments:
    mov eax, ELF_ERR_NO_SEGMENTS
    jmp .cleanup

.too_big:
    mov eax, ELF_ERR_TOO_BIG
    jmp .cleanup

.error:
    ; RAX already has error code

.cleanup:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    add rsp, 64
    pop rbp
    ret

;==============================================================================
; get_elf_entry_point
; Returns the entry point from the last loaded ELF
;
; Output: RAX = entry point address
;==============================================================================
get_elf_entry_point:
    mov rax, [elf_entry_point]
    ret

;==============================================================================
; get_elf_load_base
; Returns the load base address from the last loaded ELF
;
; Output: RAX = load base address
;==============================================================================
get_elf_load_base:
    mov rax, [elf_load_base]
    ret
