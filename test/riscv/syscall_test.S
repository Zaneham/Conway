# syscall_test.S - Test various Linux syscalls
# "Testing the plumbing before turning on the taps"
# Uses fixed addresses for buffers (0x2000 = stat, 0x2100 = winsize, 0x2200 = path)

.section .text
.global _start

_start:
    # Test 1: fstat on stdout (should succeed)
    li      a7, 80              # syscall: fstat
    li      a0, 1               # fd: stdout
    li      a1, 0x2000          # buffer at fixed address
    ecall

    # a0 should be 0 (success)
    bnez    a0, .fail_fstat

    # Test 2: close on fd 10 (should succeed - we're lenient)
    li      a7, 57              # syscall: close
    li      a0, 10              # fd: 10 (arbitrary)
    ecall

    # a0 should be 0
    bnez    a0, .fail_close

    # Test 3: ioctl TIOCGWINSZ on stdout
    li      a7, 29              # syscall: ioctl
    li      a0, 1               # fd: stdout
    lui     a1, 5               # a1 = 0x5000
    addi    a1, a1, 0x413       # a1 = 0x5413 (TIOCGWINSZ)
    li      a2, 0x2100          # buffer at fixed address
    ecall

    # a0 should be 0
    bnez    a0, .fail_ioctl

    # Check winsize values (ws_col should be 80)
    li      t0, 0x2100          # winsize buffer address
    lh      t1, 2(t0)           # ws_col at offset 2
    li      t2, 80
    bne     t1, t2, .fail_winsize

    # Test 4: openat (should fail with -ENOENT = -2)
    li      a7, 56              # syscall: openat
    li      a0, -100            # AT_FDCWD
    li      a1, 0x2200          # path at fixed address (doesn't matter, we always fail)
    li      a2, 0               # flags: O_RDONLY
    li      a3, 0               # mode
    ecall

    # a0 should be -2 (ENOENT)
    li      t0, -2
    bne     a0, t0, .fail_openat

    # All tests passed!
    li      a7, 93              # exit
    li      a0, 42              # magic success code
    ecall

.fail_fstat:
    li      a7, 93
    li      a0, 1
    ecall

.fail_close:
    li      a7, 93
    li      a0, 2
    ecall

.fail_ioctl:
    li      a7, 93
    li      a0, 3
    ecall

.fail_winsize:
    li      a7, 93
    li      a0, 4
    ecall

.fail_openat:
    li      a7, 93
    li      a0, 5
    ecall
