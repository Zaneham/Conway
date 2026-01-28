# ioctl_debug.S - Debug ioctl syscall
# Exit with a0 value after ioctl

.section .text
.global _start

_start:
    # ioctl(1, 0x5413, buf)
    li      a7, 29              # syscall: ioctl
    li      a0, 1               # fd: stdout
    li      a1, 0x5413          # request: TIOCGWINSZ
    la      a2, winsize_buf     # buffer
    ecall

    # Exit with ioctl return value (should be 0)
    # If negative, make it positive for exit code
    bgez    a0, .do_exit
    neg     a0, a0              # negate to see the errno

.do_exit:
    mv      t0, a0              # save return value
    li      a7, 93
    mv      a0, t0
    ecall

.section .data
winsize_buf:
    .space 8
