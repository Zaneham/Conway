# strcpy_large_addr_test.S - Test string copy at Doom-like addresses
# Doom uses addresses around 0x763628

.section .text
.global _start

_start:
    li sp, 0x6FFFF0         # Stack like Doom
    li gp, 0x68e00          # GP like Doom

    # Initialize heap_ptr at gp-1912 = 0x68688
    li t0, 0x163588         # Start of zone (like Doom)
    sd t0, -1912(gp)

    # Simulate zone allocation of 6MB
    li t1, 0x600000         # 6MB
    add t0, t0, t1          # End of zone = 0x763588
    sd t0, -1912(gp)

    # Now allocate a small buffer for path (like Doom does after zone)
    ld a4, -1912(gp)        # a4 = heap_ptr = 0x763588
    li a0, 256              # Buffer size
    addi a0, a0, 15
    andi a0, a0, -16
    add t1, a0, a4          # New heap_ptr
    sd t1, -1912(gp)
    mv s0, a4               # s0 = allocated buffer at ~0x763588

    # Print buffer address for debug via write syscall
    # First convert address to ASCII hex and store at 0x10000
    li s1, 0x10000          # Temp buffer for hex output
    mv a0, s0               # Address to print
    li t1, 8                # 8 hex digits
    add s2, s1, t1          # End of buffer
    mv t2, s1               # Current position

addr_to_hex:
    beqz t1, hex_done
    srli t3, a0, 60         # Get top nibble
    andi t3, t3, 0xF
    li t4, 10
    blt t3, t4, digit
    addi t3, t3, 'A' - 10
    j store_char
digit:
    addi t3, t3, '0'
store_char:
    sb t3, 0(t2)
    addi t2, t2, 1
    slli a0, a0, 4
    addi t1, t1, -1
    j addr_to_hex

hex_done:
    li t3, 10               # newline
    sb t3, 0(t2)

    # Write the address
    li a7, 64
    li a0, 1
    mv a1, s1
    li a2, 9
    ecall

    # Now copy "test.txt\0" to the buffer at s0 (~0x763588)
    la a1, msg              # Source
    mv a2, s0               # Dest

copy_loop:
    lbu t0, 0(a1)
    sb t0, 0(a2)
    beqz t0, copy_done
    addi a1, a1, 1
    addi a2, a2, 1
    j copy_loop

copy_done:
    # Verify bytes
    lbu t0, 0(s0)
    li t4, 0x74             # 't'
    bne t0, t4, fail1

    lbu t0, 1(s0)
    li t4, 0x65             # 'e'
    bne t0, t4, fail2

    # Write the copied string back via syscall
    li a7, 64
    li a0, 1
    mv a1, s0               # Buffer address
    li a2, 8
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

.section .rodata
msg: .ascii "test.txt\0"
