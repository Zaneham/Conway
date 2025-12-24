; test_phase5.asm - Phase 5 ELF Loader Tests
; "One does not simply walk into an ELF loader without testing it first"
bits 64
default rel

extern validate_elf_header
extern load_elf
extern elf_entry_point
extern elf_load_base
extern ExitProcess
extern GetStdHandle
extern WriteConsoleA

section .data
    msg_header      db "=== Phase 5: ELF Loader Tests ===", 13, 10, 0
    msg_header_len  equ $ - msg_header - 1

    msg_valid       db "Valid RISC-V ELF64... ", 0
    msg_valid_len   equ $ - msg_valid - 1

    msg_bad_magic   db "Reject bad magic... ", 0
    msg_bad_magic_len equ $ - msg_bad_magic - 1

    msg_bad_class   db "Reject 32-bit... ", 0
    msg_bad_class_len equ $ - msg_bad_class - 1

    msg_bad_endian  db "Reject big-endian... ", 0
    msg_bad_endian_len equ $ - msg_bad_endian - 1

    msg_bad_machine db "Reject non-RISC-V... ", 0
    msg_bad_machine_len equ $ - msg_bad_machine - 1

    msg_load_elf    db "Load simple ELF... ", 0
    msg_load_elf_len equ $ - msg_load_elf - 1

    msg_entry_point db "Entry point correct... ", 0
    msg_entry_len   equ $ - msg_entry_point - 1

    msg_pass        db "PASS", 13, 10, 0
    msg_pass_len    equ $ - msg_pass - 1

    msg_fail        db "FAIL", 13, 10, 0
    msg_fail_len    equ $ - msg_fail - 1

    ;==========================================================================
    ; Mock ELF Headers - Like the real thing but more fictional
    ;==========================================================================

    ; Valid RISC-V ELF64 little-endian executable header (64 bytes)
    ; Lovingly hand-crafted like a artisanal cheese, but less smelly
    align 8
    valid_elf_header:
        db 0x7F, 'E', 'L', 'F'      ; e_ident[0..3]: Magic number
        db 2                         ; e_ident[4]: ELFCLASS64
        db 1                         ; e_ident[5]: ELFDATA2LSB (little-endian)
        db 1                         ; e_ident[6]: EV_CURRENT
        db 0                         ; e_ident[7]: ELFOSABI_NONE
        dq 0                         ; e_ident[8..15]: padding
        dw 2                         ; e_type: ET_EXEC
        dw 0xF3                      ; e_machine: EM_RISCV (243)
        dd 1                         ; e_version: EV_CURRENT
        dq 0x10000                   ; e_entry: Entry point (our test expects this)
        dq 64                        ; e_phoff: Programme header offset (right after this header)
        dq 0                         ; e_shoff: Section header offset (we don't care)
        dd 0                         ; e_flags
        dw 64                        ; e_ehsize: ELF header size
        dw 56                        ; e_phentsize: Programme header entry size
        dw 1                         ; e_phnum: One programme header
        dw 64                        ; e_shentsize: Section header size (not used)
        dw 0                         ; e_shnum: No section headers
        dw 0                         ; e_shstrndx: No string table

    ; Bad magic - just a JPEG having an identity crisis
    align 8
    bad_magic_header:
        db 0xFF, 0xD8, 0xFF, 0xE0   ; JPEG magic, pretending to be an ELF
        db 2, 1, 1, 0               ; rest of ident
        dq 0
        dw 2, 0xF3
        dd 1
        times 40 db 0

    ; 32-bit ELF - In this economy? I think not.
    align 8
    bad_class_header:
        db 0x7F, 'E', 'L', 'F'
        db 1                         ; ELFCLASS32 (wrong!)
        db 1, 1, 0
        dq 0
        dw 2, 0xF3
        dd 1
        times 40 db 0

    ; Big-endian - The wrong way round, like driving on the right
    align 8
    bad_endian_header:
        db 0x7F, 'E', 'L', 'F'
        db 2
        db 2                         ; ELFDATA2MSB (big-endian, the dark side)
        db 1, 0
        dq 0
        dw 2, 0xF3
        dd 1
        times 40 db 0

    ; x86-64 ELF - Wrong architecture, mate. This is a RISC-V pub.
    align 8
    bad_machine_header:
        db 0x7F, 'E', 'L', 'F'
        db 2, 1, 1, 0
        dq 0
        dw 2
        dw 0x3E                      ; EM_X86_64 (not RISC-V!)
        dd 1
        times 40 db 0

    ;==========================================================================
    ; Complete Mock ELF File - A tiny but valid RISC-V executable
    ; Contains one PT_LOAD segment with some RISC-V instructions
    ;==========================================================================
    align 8
    mock_elf_file:
        ; ELF Header (64 bytes)
        db 0x7F, 'E', 'L', 'F'      ; Magic
        db 2, 1, 1, 0               ; Class, Data, Version, OS/ABI
        dq 0                         ; Padding
        dw 2                         ; ET_EXEC
        dw 0xF3                      ; EM_RISCV
        dd 1                         ; Version
        dq 0x1000                    ; e_entry: 0x1000 (where our code lives)
        dq 64                        ; e_phoff: Programme headers at offset 64
        dq 0                         ; e_shoff: No section headers
        dd 0                         ; e_flags
        dw 64                        ; e_ehsize
        dw 56                        ; e_phentsize
        dw 1                         ; e_phnum: One segment
        dw 0, 0, 0                   ; Section header stuff (unused)

        ; Programme Header (56 bytes) - Starting at offset 64
        dd 1                         ; p_type: PT_LOAD
        dd 5                         ; p_flags: PF_R | PF_X
        dq 120                       ; p_offset: Code starts at offset 120 in file
        dq 0x1000                    ; p_vaddr: Load at 0x1000
        dq 0x1000                    ; p_paddr: Physical address (same)
        dq 16                        ; p_filesz: 16 bytes of code (4 instructions)
        dq 16                        ; p_memsz: Same as filesz
        dq 4                         ; p_align

        ; Code Section - Starting at offset 120 (4 RISC-V instructions)
        ; This is a tiny programme that does: x1 = 42, x2 = x1 + 1
        dd 0x02A00093               ; addi x1, x0, 42
        dd 0x00108113               ; addi x2, x1, 1
        dd 0x00000013               ; nop (addi x0, x0, 0)
        dd 0x00000013               ; nop

    mock_elf_size equ $ - mock_elf_file

    tests_passed    dq 0
    stdout_handle   dq 0

section .bss
    bytes_written   resd 1
    alignb 8
    guest_memory    resb 65536      ; 64KB of guest memory, as is tradition

section .text
    global main

main:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    push rbx
    push r12

    ; Get stdout handle - for our verbose reporting needs
    mov ecx, -11
    call GetStdHandle
    mov [stdout_handle], rax

    ; Print header
    lea rcx, [msg_header]
    mov edx, msg_header_len
    call print_string

    ;==========================================================================
    ; Test 1: Valid RISC-V ELF64 header should pass validation
    ;==========================================================================
    lea rcx, [msg_valid]
    mov edx, msg_valid_len
    call print_string

    lea rdi, [valid_elf_header]
    call validate_elf_header
    test eax, eax
    jnz .valid_fail

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .test_bad_magic

.valid_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.test_bad_magic:
    ;==========================================================================
    ; Test 2: Reject file with wrong magic (not ELF)
    ;==========================================================================
    lea rcx, [msg_bad_magic]
    mov edx, msg_bad_magic_len
    call print_string

    lea rdi, [bad_magic_header]
    call validate_elf_header
    cmp eax, 1                      ; Should return ELF_ERR_NOT_ELF (1)
    jne .bad_magic_fail

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .test_bad_class

.bad_magic_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.test_bad_class:
    ;==========================================================================
    ; Test 3: Reject 32-bit ELF
    ;==========================================================================
    lea rcx, [msg_bad_class]
    mov edx, msg_bad_class_len
    call print_string

    lea rdi, [bad_class_header]
    call validate_elf_header
    cmp eax, 2                      ; Should return ELF_ERR_NOT_64BIT (2)
    jne .bad_class_fail

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .test_bad_endian

.bad_class_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.test_bad_endian:
    ;==========================================================================
    ; Test 4: Reject big-endian ELF
    ;==========================================================================
    lea rcx, [msg_bad_endian]
    mov edx, msg_bad_endian_len
    call print_string

    lea rdi, [bad_endian_header]
    call validate_elf_header
    cmp eax, 3                      ; Should return ELF_ERR_NOT_LE (3)
    jne .bad_endian_fail

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .test_bad_machine

.bad_endian_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.test_bad_machine:
    ;==========================================================================
    ; Test 5: Reject non-RISC-V ELF
    ;==========================================================================
    lea rcx, [msg_bad_machine]
    mov edx, msg_bad_machine_len
    call print_string

    lea rdi, [bad_machine_header]
    call validate_elf_header
    cmp eax, 4                      ; Should return ELF_ERR_NOT_RISCV (4)
    jne .bad_machine_fail

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .test_load_elf

.bad_machine_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.test_load_elf:
    ;==========================================================================
    ; Test 6: Load a mock ELF file into guest memory
    ;==========================================================================
    lea rcx, [msg_load_elf]
    mov edx, msg_load_elf_len
    call print_string

    ; Clear guest memory first (like a good housekeeper)
    lea rdi, [guest_memory]
    mov rcx, 65536
    xor eax, eax
.clear_mem:
    mov [rdi], al
    inc rdi
    dec rcx
    jnz .clear_mem

    ; Load the mock ELF
    lea rdi, [mock_elf_file]        ; ELF file pointer
    mov rsi, mock_elf_size          ; ELF file size
    lea rdx, [guest_memory]         ; Guest memory pointer
    mov rcx, 65536                  ; Guest memory size
    call load_elf

    test eax, eax
    jnz .load_fail

    ; Verify code was loaded at vaddr 0x1000
    ; The first instruction should be 0x02A00093 (addi x1, x0, 42)
    lea rbx, [guest_memory]
    mov eax, [rbx + 0x1000]
    cmp eax, 0x02A00093
    jne .load_fail

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .test_entry_point

.load_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.test_entry_point:
    ;==========================================================================
    ; Test 7: Entry point correctly detected
    ;==========================================================================
    lea rcx, [msg_entry_point]
    mov edx, msg_entry_len
    call print_string

    mov rax, [elf_entry_point]
    cmp rax, 0x1000                 ; Entry point should be 0x1000
    jne .entry_fail

    inc qword [tests_passed]
    lea rcx, [msg_pass]
    mov edx, msg_pass_len
    call print_string
    jmp .summary

.entry_fail:
    lea rcx, [msg_fail]
    mov edx, msg_fail_len
    call print_string

.summary:
    ; Exit with number of tests passed (should be 7)
    pop r12
    pop rbx
    mov ecx, [tests_passed]
    call ExitProcess

;------------------------------------------------------------------------------
; print_string - Prints a string to stdout
; Input: RCX = string pointer, EDX = length
;------------------------------------------------------------------------------
print_string:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov r8, rcx                     ; Save string pointer
    mov r9d, edx                    ; Save length
    mov rcx, [stdout_handle]
    mov rdx, r8
    mov r8d, r9d
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteConsoleA
    leave
    ret
