; platform_linux.asm - Linux platform implementation
; Provides platform-agnostic interface for OS calls

bits 64
default rel

; Linux syscall numbers (x86_64)
SYS_WRITE       equ 1
SYS_MPROTECT    equ 10
SYS_EXIT        equ 60

; mprotect flags
PROT_READ       equ 1
PROT_WRITE      equ 2
PROT_EXEC       equ 4

; File descriptors
STDOUT_FD       equ 1

; Export platform functions
global plat_exit
global plat_write_stdout
global plat_make_executable
global plat_init

section .text

;==============================================================================
; plat_init - Initialize platform
; On Linux, nothing to do (stdout is always fd 1)
;==============================================================================
plat_init:
    ret

;==============================================================================
; plat_exit - Exit process with code
; Input: EDI = exit code (Linux calling convention)
;        ECX = exit code (Windows calling convention - we accept both)
;==============================================================================
plat_exit:
    ; Accept exit code from either RDI (Linux) or RCX (Windows convention)
    ; If called from Linux code, RDI has it. If from portable code using RCX, use that.
    test edi, edi
    jnz .use_edi
    mov edi, ecx                    ; Use Windows convention param if RDI is 0
.use_edi:
    mov eax, SYS_EXIT
    syscall
    ; Never returns

;==============================================================================
; plat_write_stdout - Write to stdout
; Input: RDI = buffer pointer, RSI = length (Linux convention)
;    OR: RCX = buffer pointer, RDX = length (Windows convention)
; Output: RAX = bytes written, or -1 on error
;==============================================================================
plat_write_stdout:
    ; We'll use Windows calling convention (RCX, RDX) for portability
    ; and convert to Linux syscall convention here
    push rdi
    push rsi

    mov rdi, STDOUT_FD              ; fd = stdout
    mov rsi, rcx                    ; buf = rcx (Windows convention)
    mov rdx, rdx                    ; count = rdx (same in both)
    mov eax, SYS_WRITE
    syscall

    ; RAX = bytes written or negative error
    pop rsi
    pop rdi
    ret

;==============================================================================
; plat_make_executable - Make memory region executable
; Input: RCX = address, RDX = size (Windows convention)
; Output: RAX = 0 on success, -1 on error
;==============================================================================
plat_make_executable:
    push rdi
    push rsi
    push rdx

    ; mprotect(addr, len, prot)
    mov rdi, rcx                            ; addr
    mov rsi, rdx                            ; len
    mov edx, PROT_READ | PROT_WRITE | PROT_EXEC  ; prot = rwx
    mov eax, SYS_MPROTECT
    syscall

    ; RAX = 0 on success, negative on error
    test rax, rax
    jns .success
    mov rax, -1
    jmp .done

.success:
    xor eax, eax

.done:
    pop rdx
    pop rsi
    pop rdi
    ret
