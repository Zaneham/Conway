# doom_path_test.S - Replicate exact Doom path construction
# Test malloc-like allocation followed by memcpy-like copy

.section .text
.global _start

_start:
    # Set up stack and GP - use smaller addresses for 2MB test runner
    li sp, 0x1F0000         # Stack at ~2MB
    li gp, 0x10000          # GP

    # Use a buffer address that fits in 2MB guest memory
    # This mimics the pattern of Doom's high-address allocations
    li s0, 0x100000         # Buffer at 1MB (well within 2MB limit)

    # Print buffer address
    li a7, 64
    li a0, 1
    la a1, msg_addr
    li a2, 5
    ecall

    mv a0, s0
    jal ra, print_hex8

    li a7, 64
    li a0, 1
    la a1, newline
    li a2, 1
    ecall

    # Now copy "./doom1.wad\0" to the buffer using memcpy-style loop
    # This mirrors the exact pattern in Doom's memcpy:
    # lbu a3, 0(a5)    - load source byte
    # addi a4, a4, 1   - increment dest pointer
    # addi a5, a5, 1   - increment source pointer
    # sb a3, -1(a4)    - store byte (with -1 offset!)

    la a5, source_str       # Source pointer
    mv a4, s0               # Dest pointer
    li a3, 12               # Length including null

copy_loop:
    lbu t0, 0(a5)           # Load source byte
    addi a4, a4, 1          # Increment dest
    addi a5, a5, 1          # Increment source
    sb t0, -1(a4)           # Store with -1 offset (like Doom's memcpy!)
    addi a3, a3, -1
    bnez a3, copy_loop

    # Print "BUF: " and buffer contents
    li a7, 64
    li a0, 1
    la a1, msg_buf
    li a2, 5
    ecall

    li a7, 64
    li a0, 1
    mv a1, s0               # Buffer address
    li a2, 11               # "./doom1.wad" length
    ecall

    li a7, 64
    li a0, 1
    la a1, newline
    li a2, 1
    ecall

    # Verify first few bytes
    lbu t0, 0(s0)           # Should be '.'
    li t1, '.'
    bne t0, t1, fail1

    lbu t0, 1(s0)           # Should be '/'
    li t1, '/'
    bne t0, t1, fail2

    lbu t0, 2(s0)           # Should be 'd'
    li t1, 'd'
    bne t0, t1, fail3

    # Success!
    li a7, 64
    li a0, 1
    la a1, msg_pass
    li a2, 5
    ecall

    li a0, 0
    li a7, 93
    ecall

fail1:
    li a7, 64
    li a0, 1
    la a1, msg_f1
    li a2, 13
    ecall
    li a0, 1
    li a7, 93
    ecall

fail2:
    li a7, 64
    li a0, 1
    la a1, msg_f2
    li a2, 13
    ecall
    li a0, 2
    li a7, 93
    ecall

fail3:
    li a7, 64
    li a0, 1
    la a1, msg_f3
    li a2, 13
    ecall
    li a0, 3
    li a7, 93
    ecall

# print_hex8 - print 8 hex digits from a0
print_hex8:
    addi sp, sp, -32
    sd ra, 24(sp)
    sd s0, 16(sp)
    sd s1, 8(sp)

    mv s0, a0
    li s1, 8
    addi a0, sp, 0

.ph8_loop:
    srli t0, s0, 60
    andi t0, t0, 0xF
    li t1, 10
    blt t0, t1, .ph8_digit
    addi t0, t0, 'A' - 10
    j .ph8_store
.ph8_digit:
    addi t0, t0, '0'
.ph8_store:
    sb t0, 0(a0)
    addi a0, a0, 1
    slli s0, s0, 4
    addi s1, s1, -1
    bnez s1, .ph8_loop

    li a7, 64
    li a0, 1
    addi a1, sp, 0
    li a2, 8
    ecall

    ld ra, 24(sp)
    ld s0, 16(sp)
    ld s1, 8(sp)
    addi sp, sp, 32
    ret

.section .rodata
source_str: .ascii "./doom1.wad\0"
msg_addr:   .ascii "ADDR:"
msg_buf:    .ascii "BUF: "
msg_pass:   .ascii "PASS\n"
msg_f1:     .ascii "FAIL: byte 0\n"
msg_f2:     .ascii "FAIL: byte 1\n"
msg_f3:     .ascii "FAIL: byte 2\n"
newline:    .ascii "\n"
