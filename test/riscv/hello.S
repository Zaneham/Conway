# hello.S - Hello World using Linux RISC-V syscall ABI
# "The traditional first programme"

.section .rodata
msg:
    .ascii "Hello from RISC-V!\n"
msg_len = . - msg

.section .text
.global _start

_start:
    # write(1, msg, msg_len)
    li      a7, 64          # syscall: write
    li      a0, 1           # fd: stdout
    la      a1, msg         # buf: message address
    li      a2, msg_len     # count: message length
    ecall

    # Check return value (should be msg_len)
    li      t0, msg_len
    bne     a0, t0, .error

    # exit(0)
    li      a7, 93          # syscall: exit
    li      a0, 0           # status: success
    ecall

.error:
    # exit(1)
    li      a7, 93
    li      a0, 1
    ecall
