; minimal_test.asm - Absolutely minimal test
bits 64
default rel

extern ExitProcess
extern GetCommandLineA

section .text
    global main

main:
    sub rsp, 40                     ; Shadow space (32) + 8 for alignment

    call GetCommandLineA
    test rax, rax
    jz .fail

    ; Success - exit 0
    xor ecx, ecx
    call ExitProcess

.fail:
    mov ecx, 1
    call ExitProcess
