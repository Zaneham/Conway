; Simple hello world test
bits 64
default rel

extern GetStdHandle
extern WriteFile
extern ExitProcess

STD_OUTPUT_HANDLE       equ -11

section .data
    msg         db "Hello, Conway!", 13, 10, 0

section .bss
    stdout      resq 1
    written     resq 1

section .text
    global main

main:
    sub rsp, 40

    ; Get stdout
    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [stdout], rax

    ; Write message
    mov rcx, rax
    lea rdx, [msg]
    mov r8d, 16
    lea r9, [written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Exit with code 42
    mov ecx, 42
    call ExitProcess
