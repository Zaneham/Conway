bits 64
default rel

PAGE_EXECUTE_READWRITE equ 0x40

section .data
    ; li t0, 100 (base address)
    instr_li_t0:    dd 0x06400293
    ; li t1, 42 (value to store)
    instr_li_t1:    dd 0x02A00313
    ; sd t1, 0(t0) - store 42 at address 100
    instr_sd:       dd 0x0062B023
    ; ld a0, 0(t0) - load from address 100 into a0
    instr_ld:       dd 0x0002B503

    fmt_t0: db "t0 = %lld", 10, 0
    fmt_t1: db "t1 = %lld", 10, 0
    fmt_a0: db "a0 = %lld (should be 42)", 10, 0

section .bss
    alignb 16
    code_buffer: resb 4096
    alignb 8
    rv_regs: resq 32
    alignb 4096
    rv_memory: resb 65536
    old_protect: resd 1
    saved_bytes: resq 1

section .text
    global main
    extern printf
    extern VirtualProtect
    extern ExitProcess
    extern translate_instruction

main:
    push rbp
    mov rbp, rsp
    sub rsp, 64

    ; VirtualProtect
    lea rcx, [code_buffer]
    mov rdx, 4096
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    ;=== li t0, 100 ===
    mov edi, [instr_li_t0]
    lea rsi, [code_buffer]
    call translate_instruction
    mov [saved_bytes], rax
    mov rax, [saved_bytes]
    lea rdi, [code_buffer]
    add rdi, rax
    mov byte [rdi], 0xC3
    lea rbx, [rv_regs]
    lea r14, [rv_memory]
    lea rax, [code_buffer]
    call rax

    lea rcx, [fmt_t0]
    lea rax, [rv_regs]
    mov rdx, [rax + 5*8]     ; t0 = x5
    call printf

    ;=== li t1, 42 ===
    mov edi, [instr_li_t1]
    lea rsi, [code_buffer]
    call translate_instruction
    mov [saved_bytes], rax
    mov rax, [saved_bytes]
    lea rdi, [code_buffer]
    add rdi, rax
    mov byte [rdi], 0xC3
    lea rbx, [rv_regs]
    lea r14, [rv_memory]
    lea rax, [code_buffer]
    call rax

    lea rcx, [fmt_t1]
    lea rax, [rv_regs]
    mov rdx, [rax + 6*8]     ; t1 = x6
    call printf

    ;=== sd t1, 0(t0) ===
    mov edi, [instr_sd]
    lea rsi, [code_buffer]
    call translate_instruction
    mov [saved_bytes], rax
    mov rax, [saved_bytes]
    lea rdi, [code_buffer]
    add rdi, rax
    mov byte [rdi], 0xC3
    lea rbx, [rv_regs]
    lea r14, [rv_memory]
    lea rax, [code_buffer]
    call rax

    ;=== ld a0, 0(t0) ===
    mov edi, [instr_ld]
    lea rsi, [code_buffer]
    call translate_instruction
    mov [saved_bytes], rax
    mov rax, [saved_bytes]
    lea rdi, [code_buffer]
    add rdi, rax
    mov byte [rdi], 0xC3
    lea rbx, [rv_regs]
    lea r14, [rv_memory]
    lea rax, [code_buffer]
    call rax

    lea rcx, [fmt_a0]
    lea rax, [rv_regs]
    mov rdx, [rax + 10*8]    ; a0 = x10
    call printf

    xor ecx, ecx
    call ExitProcess
