; platform_win.asm - Windows platform implementation
; Provides platform-agnostic interface for OS calls

bits 64
default rel

; Windows API imports
extern ExitProcess
extern GetStdHandle
extern WriteFile
extern VirtualProtect

; Export platform functions
global plat_exit
global plat_write_stdout
global plat_make_executable
global plat_init
; Export these for translator.asm debug output
global stdout_handle
global bytes_written

section .data
    stdout_handle   dq 0

section .bss
    plat_old_protect     resd 1
    bytes_written   resq 1

section .text

;==============================================================================
; plat_init - Initialize platform (get stdout handle, etc.)
; Call this once at startup
;==============================================================================
plat_init:
    push rbp
    mov rbp, rsp
    sub rsp, 32

    ; Get stdout handle
    mov ecx, -11                    ; STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [stdout_handle], rax

    leave
    ret

;==============================================================================
; plat_exit - Exit process with code
; Input: ECX = exit code
;==============================================================================
plat_exit:
    sub rsp, 40
    call ExitProcess
    ; Never returns

;==============================================================================
; plat_write_stdout - Write to stdout
; Input: RCX = buffer pointer, RDX = length
; Output: RAX = bytes written, or -1 on error
;==============================================================================
plat_write_stdout:
    push rbp
    mov rbp, rsp
    sub rsp, 48

    ; Save params
    mov r8, rdx                     ; length -> r8 (nNumberOfBytesToWrite)
    mov rdx, rcx                    ; buffer -> rdx (lpBuffer)

    mov rcx, [stdout_handle]        ; hFile
    lea r9, [bytes_written]         ; lpNumberOfBytesWritten
    mov qword [rsp+32], 0           ; lpOverlapped = NULL

    call WriteFile

    test eax, eax
    jz .error
    mov rax, [bytes_written]
    jmp .done

.error:
    mov rax, -1

.done:
    leave
    ret

;==============================================================================
; plat_make_executable - Make memory region executable
; Input: RCX = address, RDX = size
; Output: RAX = 0 on success, -1 on error
;==============================================================================
plat_make_executable:
    push rbp
    mov rbp, rsp
    sub rsp, 48

    ; VirtualProtect(addr, size, PAGE_EXECUTE_READWRITE, &old_protect)
    ; rcx = addr (already set)
    ; rdx = size (already set)
    mov r8d, 0x40                   ; PAGE_EXECUTE_READWRITE
    lea r9, [plat_old_protect]

    call VirtualProtect

    test eax, eax
    jz .error
    xor eax, eax                    ; Success = 0
    jmp .done

.error:
    mov eax, -1

.done:
    leave
    ret
