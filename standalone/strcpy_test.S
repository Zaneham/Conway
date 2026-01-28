# strcpy_test.S - Test string copy to heap memory
# This tests the same operations Doom uses for WAD path construction

.section .text
.global _start

_start:
    li sp, 0xFFF0
    li gp, 0x8000

    # Initialize heap_ptr at gp-1912 = 0x7888
    li t0, 0x9000
    sd t0, -1912(gp)

    # Simulate malloc(32) for path buffer
    ld a4, -1912(gp)        # a4 = old heap_ptr
    li a0, 32
    addi a0, a0, 15
    andi a0, a0, -16        # Round up to 16
    add a0, a0, a4          # New heap_ptr
    sd a0, -1912(gp)        # Store new heap_ptr
    mv s0, a4               # s0 = allocated buffer at 0x9000

    # Now copy "test.txt\0" to the buffer
    # Source string is at msg label
    la a1, msg              # a1 = source pointer
    mv a2, s0               # a2 = dest pointer

copy_loop:
    lbu t0, 0(a1)           # Load byte from source
    sb t0, 0(a2)            # Store byte to dest
    beqz t0, copy_done      # If null terminator, done
    addi a1, a1, 1          # Increment source
    addi a2, a2, 1          # Increment dest
    j copy_loop

copy_done:
    # Verify: read back first 4 bytes from buffer
    lbu t0, 0(s0)           # Should be 't' = 0x74
    lbu t1, 1(s0)           # Should be 'e' = 0x65
    lbu t2, 2(s0)           # Should be 's' = 0x73
    lbu t3, 3(s0)           # Should be 't' = 0x74

    # Check first byte
    li t4, 0x74             # 't'
    bne t0, t4, fail1

    # Check second byte
    li t4, 0x65             # 'e'
    bne t1, t4, fail2

    # Check third byte
    li t4, 0x73             # 's'
    bne t2, t4, fail3

    # Check fourth byte
    li t4, 0x74             # 't'
    bne t3, t4, fail4

    # All passed - call write syscall with the buffer
    li a7, 64               # write syscall
    li a0, 1                # stdout
    mv a1, s0               # buffer = "test.txt"
    li a2, 8                # length
    ecall

    # Success
    li a0, 0
    li a7, 93
    ecall

fail1:
    li a0, 1
    li a7, 93
    ecall

fail2:
    li a0, 2
    li a7, 93
    ecall

fail3:
    li a0, 3
    li a7, 93
    ecall

fail4:
    li a0, 4
    li a7, 93
    ecall

.section .rodata
msg: .ascii "test.txt\0"
