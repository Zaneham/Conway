# ioctl_minimal.S - Minimal ioctl test
# Just test that we reach the ioctl handler

.section .text
.global _start

_start:
    # Store 42 in a0 before calling ioctl
    # If ioctl returns something else, we know it ran
    li      a0, 42

    # ioctl(1, 0x5413, 0x2000)  - buffer at fixed guest address
    li      a7, 29              # syscall: ioctl
    li      a0, 1               # fd: stdout
    lui     a1, 5               # a1 = 0x5000
    addi    a1, a1, 0x413       # a1 = 0x5413
    li      a2, 0x2000          # buffer at 0x2000 (in guest memory)
    ecall

    # Exit with return value
    mv      t0, a0
    li      a7, 93
    mv      a0, t0
    ecall

.section .data
    .space 8
