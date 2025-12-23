; Conway - RISC-V to x86-64 Binary Translator
; runtime.asm - Runtime support and memory management
;
; Manages execution context, register state, and memory operations

section .data
    ; Memory protection constants (Windows)
    PAGE_EXECUTE_READWRITE equ 0x40
    MEM_COMMIT             equ 0x1000
    MEM_RESERVE            equ 0x2000

section .bss
    ; RISC-V memory space (4 MiB guest memory)
    rv_memory       resb 4194304
    rv_memory_size  equ 4194304

    ; Translation cache metadata
    cache_entries   resq 4096       ; Cached translation addresses
    cache_valid     resb 4096       ; Validity flags

section .text
    global runtime_init
    global runtime_cleanup
    global runtime_read_byte
    global runtime_read_half
    global runtime_read_word
    global runtime_read_dword
    global runtime_write_byte
    global runtime_write_half
    global runtime_write_word
    global runtime_write_dword
    global runtime_translate_address
    global runtime_invalidate_cache

    extern rv_regs
    extern rv_pc
    extern code_buffer
    extern code_ptr

; runtime_init - Initialise the runtime environment
; Output: rax = 1 on success, 0 on failure
runtime_init:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    ; Initialise RISC-V registers to zero
    lea rdi, [rel rv_regs]
    xor eax, eax
    mov ecx, 256                ; 32 registers * 8 bytes
    rep stosb

    ; Initialise programme counter
    mov qword [rel rv_pc], 0

    ; Clear translation cache
    lea rdi, [rel cache_valid]
    xor eax, eax
    mov ecx, 4096
    rep stosb

    ; Clear guest memory
    lea rdi, [rel rv_memory]
    xor eax, eax
    mov ecx, rv_memory_size
    rep stosb

    ; Initialise stack pointer (x2/sp) to top of memory
    lea rax, [rel rv_memory]
    add rax, rv_memory_size
    lea rbx, [rel rv_regs]
    mov [rbx + 2*8], rax        ; x2 = sp

    ; Success
    mov eax, 1

    pop r12
    pop rbx
    pop rbp
    ret

; runtime_cleanup - Clean up runtime resources
runtime_cleanup:
    push rbp
    mov rbp, rsp

    ; Nothing to clean up currently
    ; Future: Free any allocated memory

    pop rbp
    ret

; runtime_translate_address - Translate RISC-V address to host address
; Input: rdi = RISC-V address
; Output: rax = host address, or 0 if invalid
runtime_translate_address:
    push rbp
    mov rbp, rsp

    ; Check bounds
    cmp rdi, rv_memory_size
    jge .invalid

    ; Calculate host address
    lea rax, [rel rv_memory]
    add rax, rdi
    jmp .done

.invalid:
    xor eax, eax

.done:
    pop rbp
    ret

; runtime_read_byte - Read a byte from RISC-V memory
; Input: rdi = RISC-V address
; Output: al = value (zero-extended in rax)
runtime_read_byte:
    push rbp
    mov rbp, rsp

    call runtime_translate_address
    test rax, rax
    jz .invalid

    movzx eax, byte [rax]
    jmp .done

.invalid:
    xor eax, eax

.done:
    pop rbp
    ret

; runtime_read_half - Read a halfword (16-bit) from RISC-V memory
; Input: rdi = RISC-V address
; Output: ax = value (zero-extended in rax)
runtime_read_half:
    push rbp
    mov rbp, rsp

    call runtime_translate_address
    test rax, rax
    jz .invalid

    movzx eax, word [rax]
    jmp .done

.invalid:
    xor eax, eax

.done:
    pop rbp
    ret

; runtime_read_word - Read a word (32-bit) from RISC-V memory
; Input: rdi = RISC-V address
; Output: eax = value (zero-extended in rax)
runtime_read_word:
    push rbp
    mov rbp, rsp

    call runtime_translate_address
    test rax, rax
    jz .invalid

    mov eax, [rax]
    jmp .done

.invalid:
    xor eax, eax

.done:
    pop rbp
    ret

; runtime_read_dword - Read a doubleword (64-bit) from RISC-V memory
; Input: rdi = RISC-V address
; Output: rax = value
runtime_read_dword:
    push rbp
    mov rbp, rsp

    call runtime_translate_address
    test rax, rax
    jz .invalid

    mov rax, [rax]
    jmp .done

.invalid:
    xor eax, eax

.done:
    pop rbp
    ret

; runtime_write_byte - Write a byte to RISC-V memory
; Input: rdi = RISC-V address, sil = value
runtime_write_byte:
    push rbp
    mov rbp, rsp
    push rbx

    mov bl, sil                 ; Save value
    call runtime_translate_address
    test rax, rax
    jz .done

    mov [rax], bl

.done:
    pop rbx
    pop rbp
    ret

; runtime_write_half - Write a halfword (16-bit) to RISC-V memory
; Input: rdi = RISC-V address, si = value
runtime_write_half:
    push rbp
    mov rbp, rsp
    push rbx

    mov bx, si
    call runtime_translate_address
    test rax, rax
    jz .done

    mov [rax], bx

.done:
    pop rbx
    pop rbp
    ret

; runtime_write_word - Write a word (32-bit) to RISC-V memory
; Input: rdi = RISC-V address, esi = value
runtime_write_word:
    push rbp
    mov rbp, rsp
    push rbx

    mov ebx, esi
    call runtime_translate_address
    test rax, rax
    jz .done

    mov [rax], ebx

.done:
    pop rbx
    pop rbp
    ret

; runtime_write_dword - Write a doubleword (64-bit) to RISC-V memory
; Input: rdi = RISC-V address, rsi = value
runtime_write_dword:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rsi
    call runtime_translate_address
    test rax, rax
    jz .done

    mov [rax], rbx

.done:
    pop rbx
    pop rbp
    ret

; runtime_invalidate_cache - Invalidate translation cache entry
; Input: rdi = RISC-V address
runtime_invalidate_cache:
    push rbp
    mov rbp, rsp

    ; Calculate cache index (address / 4, masked to cache size)
    mov rax, rdi
    shr rax, 2
    and eax, 0xFFF              ; 4096 entries

    ; Clear validity flag
    lea rcx, [rel cache_valid]
    mov byte [rcx + rax], 0

    pop rbp
    ret
