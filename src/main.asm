; Conway - RISC-V to x86-64 Binary Translator
; main.asm - Entry point and initialisation
;
; Named after Lynn Conway, pioneer of dynamic instruction handling

%include "rv_opcodes.inc"
%include "x86_opcodes.inc"

section .data
    banner      db "Conway - RISC-V to x86-64 Binary Translator", 10, 0
    usage_msg   db "Usage: conway <riscv_binary>", 10, 0
    err_nofile  db "Error: Could not open input file", 10, 0
    err_memory  db "Error: Memory allocation failed", 10, 0

section .bss
    ; RISC-V register file (x0-x31, 64-bit each)
    rv_regs     resq 32

    ; Programme counter
    rv_pc       resq 1

    ; Code buffer for emitted x86-64
    code_buffer resb 1048576     ; 1 MiB translation buffer
    code_ptr    resq 1

    ; Input binary buffer
    input_buf   resb 16777216    ; 16 MiB max input
    input_size  resq 1

section .text
    global main
    extern decode_instruction
    extern dispatch_handler
    extern emit_prologue
    extern emit_epilogue
    extern runtime_init
    extern runtime_cleanup

; Entry point
main:
    push rbp
    mov rbp, rsp
    sub rsp, 32                 ; Shadow space for Windows x64 ABI

    ; Save command line arguments
    mov [rbp-8], rcx            ; argc
    mov [rbp-16], rdx           ; argv

    ; Initialise runtime
    call runtime_init
    test rax, rax
    jz .init_failed

    ; Check arguments
    mov rcx, [rbp-8]
    cmp rcx, 2
    jl .show_usage

    ; Get input filename from argv[1]
    mov rax, [rbp-16]
    mov rcx, [rax+8]            ; argv[1]

    ; Load the RISC-V binary
    call load_binary
    test rax, rax
    jz .load_failed

    ; Initialise code buffer pointer
    lea rax, [rel code_buffer]
    mov [rel code_ptr], rax

    ; Emit prologue (set up x86-64 context)
    call emit_prologue

    ; Main translation loop
    call translate_loop

    ; Emit epilogue
    call emit_epilogue

    ; Execute translated code
    call execute_translated

    ; Clean up
    call runtime_cleanup

    ; Exit success
    xor eax, eax
    jmp .exit

.show_usage:
    lea rcx, [rel usage_msg]
    call print_string
    mov eax, 1
    jmp .exit

.init_failed:
.load_failed:
    lea rcx, [rel err_nofile]
    call print_string
    mov eax, 1
    jmp .exit

.exit:
    add rsp, 32
    pop rbp
    ret

; translate_loop - Main translation loop
; Iterates through RISC-V instructions and emits x86-64 code
translate_loop:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    ; r12 = current position in input
    ; r13 = end of input
    lea r12, [rel input_buf]
    mov r13, [rel input_size]
    add r13, r12

.loop:
    cmp r12, r13
    jge .done

    ; Fetch 32-bit RISC-V instruction
    mov edi, [r12]

    ; Decode instruction
    call decode_instruction
    ; Returns: rax = decoded instruction info

    ; Dispatch to appropriate handler
    mov rdi, rax
    call dispatch_handler

    ; Advance to next instruction
    add r12, 4
    jmp .loop

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; execute_translated - Execute the translated x86-64 code
execute_translated:
    push rbp
    mov rbp, rsp

    ; Make code buffer executable (platform-specific)
    ; TODO: VirtualProtect on Windows, mprotect on Linux

    ; Jump to translated code
    lea rax, [rel code_buffer]
    call rax

    pop rbp
    ret

; load_binary - Load RISC-V binary from file
; Input: rcx = filename
; Output: rax = success (1) or failure (0)
load_binary:
    push rbp
    mov rbp, rsp
    ; TODO: Implement file loading
    ; For now, return success
    mov eax, 1
    pop rbp
    ret

; print_string - Print null-terminated string
; Input: rcx = string pointer
print_string:
    push rbp
    mov rbp, rsp
    ; TODO: Implement using WriteConsoleA on Windows
    pop rbp
    ret
