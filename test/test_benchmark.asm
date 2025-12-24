; test_benchmark.asm - Measure execution time (simple version)
; Returns timing info via checkpoints
bits 64
default rel

extern load_elf
extern init_block_cache
extern execute_blocks
extern code_buffer
extern ExitProcess
extern VirtualProtect
extern CreateFileA
extern ReadFile
extern CloseHandle
extern QueryPerformanceCounter
extern QueryPerformanceFrequency

PAGE_EXECUTE_READWRITE  equ 0x40
GENERIC_READ            equ 0x80000000
FILE_SHARE_READ         equ 1
OPEN_EXISTING           equ 3
FILE_ATTRIBUTE_NORMAL   equ 0x80
INVALID_HANDLE_VALUE    equ -1

section .data
    elf_path        db "test/riscv/fib_bench.elf", 0

section .bss
    old_protect     resd 1
    alignb 8
    file_handle     resq 1
    bytes_read      resq 1
    elf_buffer      resb 65536
    guest_memory    resb 65536
    rv_regs         resq 32
    rv_pc           resq 1
    perf_freq       resq 1
    time_start      resq 1
    time_end        resq 1

section .text
    global main

main:
    push rbp
    mov rbp, rsp
    sub rsp, 128
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Get performance frequency
    lea rcx, [perf_freq]
    call QueryPerformanceFrequency

    ; === Setup (not timed - just get it done) ===
    lea rcx, [code_buffer]
    mov rdx, 1048576
    mov r8d, PAGE_EXECUTE_READWRITE
    lea r9, [old_protect]
    call VirtualProtect

    call init_block_cache

    ; Open file
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

    mov rcx, [file_handle]
    lea rdx, [elf_buffer]
    mov r8d, 65536
    lea r9, [bytes_read]
    mov qword [rsp+32], 0
    call ReadFile

    mov rcx, [file_handle]
    call CloseHandle

    lea rdi, [elf_buffer]
    mov rsi, [bytes_read]
    lea rdx, [guest_memory]
    mov rcx, 65536
    call load_elf
    test eax, eax
    jnz .fail

    ; === First run: Cold (translation + execution) ===
    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 32
.clr1:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .clr1

    lea rcx, [time_start]
    call QueryPerformanceCounter

    xor edi, edi
    lea rsi, [guest_memory]
    add rsi, 0x1000
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8d, 1000
    call execute_blocks

    lea rcx, [time_end]
    call QueryPerformanceCounter

    ; Calculate first run time in microseconds
    mov rax, [time_end]
    sub rax, [time_start]
    imul rax, 1000000           ; Convert to microseconds
    xor edx, edx
    div qword [perf_freq]
    mov r12, rax                ; R12 = first run time (us)

    ; Save result
    lea rax, [rv_regs]
    mov r15d, [rax + 80]        ; R15 = result (a0)

    ; === 100 cached runs ===
    lea rcx, [time_start]
    call QueryPerformanceCounter

    mov r13d, 100
.loop100:
    lea rdi, [rv_regs]
    xor eax, eax
    mov ecx, 32
.clr2:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .clr2

    xor edi, edi
    lea rsi, [guest_memory]
    add rsi, 0x1000
    lea rdx, [rv_regs]
    lea rcx, [rv_pc]
    mov r8d, 1000
    call execute_blocks

    dec r13d
    jnz .loop100

    lea rcx, [time_end]
    call QueryPerformanceCounter

    ; Calculate 100 runs time in microseconds
    mov rax, [time_end]
    sub rax, [time_start]
    imul rax, 1000000
    xor edx, edx
    div qword [perf_freq]
    mov r14, rax                ; R14 = 100 runs time (us)

    ; Exit code format: encode timing info
    ; We'll use a simple scheme: exit with first_run_us / 10
    ; (since exit codes are limited to 255)

    ; Actually let's just verify result and print times via exit codes
    ; Run 1: exit with first_run_ms
    ; We'll need multiple runs to get all data

    ; For now, exit with first run time in ms (or 255 if > 255)
    mov rax, r12
    xor edx, edx
    mov ecx, 1000
    div ecx                     ; RAX = first run in ms
    cmp eax, 255
    jle .cap1
    mov eax, 255
.cap1:
    mov ecx, eax
    jmp .exit

.fail:
    mov ecx, 254

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    add rsp, 128
    pop rbp
    sub rsp, 40
    call ExitProcess
