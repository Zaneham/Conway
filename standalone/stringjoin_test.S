# stringjoin_test.S - Mimic M_StringJoin logic to debug Doom path issue
#
# M_StringJoin(".", "/", "doom1.wad", NULL) should produce "./doom1.wad"

.section .text
.global _start

_start:
    li sp, 0x6FFF0
    li gp, 0x68e00

    # Initialize heap_ptr at gp-1912 = 0x68688
    li t0, 0x763588             # Start where Doom would (after zone)
    sd t0, -1912(gp)

    # Call our string_join with (".", "/", "doom1.wad", NULL)
    la a0, str_dot              # First arg: "."
    la a1, str_slash            # Second arg: "/"
    la a2, str_wad              # Third arg: "doom1.wad"
    li a3, 0                    # Null terminator
    jal ra, string_join

    # a0 now has the result buffer address
    mv s0, a0                   # Save result

    # Debug: Print result address
    li a7, 64
    li a0, 1
    la a1, msg_addr
    li a2, 6
    ecall

    # Print result address as hex (8 digits)
    mv a0, s0                   # Address to print
    jal ra, print_hex8

    # Print newline
    li a7, 64
    li a0, 1
    la a1, newline
    li a2, 1
    ecall

    # Debug: Print buffer contents
    li a7, 64
    li a0, 1
    la a1, msg_buf
    li a2, 5
    ecall

    # Print buffer contents using write syscall
    li a7, 64
    li a0, 1
    mv a1, s0                   # Buffer address
    li a2, 12                   # "./doom1.wad" = 11 chars
    ecall

    # Print newline
    li a7, 64
    li a0, 1
    la a1, newline
    li a2, 1
    ecall

    # Verify buffer contents byte by byte
    lbu t0, 0(s0)               # Should be '.'
    li t1, '.'
    bne t0, t1, fail1

    lbu t0, 1(s0)               # Should be '/'
    li t1, '/'
    bne t0, t1, fail2

    lbu t0, 2(s0)               # Should be 'd'
    li t1, 'd'
    bne t0, t1, fail3

    lbu t0, 3(s0)               # Should be 'o'
    li t1, 'o'
    bne t0, t1, fail4

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

# string_join(a0, a1, a2, a3, ...) - join strings with varargs
# Returns pointer to joined string in a0
string_join:
    addi sp, sp, -128
    sd ra, 56(sp)
    sd s0, 48(sp)
    sd s1, 40(sp)
    sd s2, 32(sp)
    sd s3, 24(sp)
    sd s4, 16(sp)

    # Save varargs to stack (like M_StringJoin does)
    sd a1, 72(sp)               # Second vararg
    sd a2, 80(sp)               # Third vararg
    sd a3, 88(sp)               # Fourth vararg (NULL)

    mv s2, a0                   # s2 = first arg (".")

    # Calculate strlen of first arg + 1
    jal ra, strlen
    addi s0, a0, 1              # s0 = len(first) + 1

    # Loop through varargs to sum lengths
    addi s4, sp, 72             # s4 = &second vararg on stack

.calc_len_loop:
    ld a5, 0(s4)                # Load vararg pointer
    beqz a5, .calc_len_done     # If NULL, done
    mv a0, a5                   # Arg for strlen
    addi s4, s4, 8              # Next vararg
    sd s4, 8(sp)                # Save s4
    mv s1, a5                   # Save current string ptr
    jal ra, strlen
    ld s4, 8(sp)                # Restore s4
    add s0, s0, a0              # Add length
    j .calc_len_loop

.calc_len_done:
    # s0 = total length needed

    # Allocate buffer (simple bump allocator)
    ld a4, -1912(gp)            # Current heap_ptr
    mv s3, a4                   # s3 = buffer start
    addi a0, s0, 15
    andi a0, a0, -16            # Round up to 16
    add a0, a0, a4              # New heap_ptr
    sd a0, -1912(gp)            # Store new heap_ptr

    # First, copy first arg to buffer
    mv a0, s3                   # dest = buffer
    addi a2, s0, -1             # length = total - 1
    add a5, a0, a2              # end position
    sb zero, 0(a5)              # null terminate
    mv a1, s2                   # src = first arg (".")
    jal ra, strncpy

    # Now loop to append each vararg
    addi s4, sp, 72             # Reset to first vararg

.copy_loop:
    ld s2, 0(s4)                # s2 = current vararg
    sd s4, 8(sp)                # Save s4
    beqz s2, .copy_done         # If NULL, done

    mv a0, s3                   # a0 = buffer
    jal ra, strlen              # a0 = current length of buffer

    bgeu s0, a0, .check_room
    mv a0, s0                   # Clamp to total
.check_room:
    sub a2, s0, a0              # a2 = remaining space

    ld s4, 8(sp)                # Restore s4
    addi s4, s4, 8              # Advance to next

    beq s0, a0, .copy_loop      # If no room, skip

    add a0, a0, s3              # a0 = buffer + current_len (dest for append)
    addi a2, a2, -1             # Leave room for null
    add a5, a0, a2              # End position
    mv a1, s2                   # src = current vararg
    sb zero, 0(a5)              # Null terminate
    jal ra, strncpy

    j .copy_loop

.copy_done:
    mv a0, s3                   # Return buffer address

    ld ra, 56(sp)
    ld s0, 48(sp)
    ld s1, 40(sp)
    ld s2, 32(sp)
    ld s3, 24(sp)
    ld s4, 16(sp)
    addi sp, sp, 128
    ret

# strlen(a0) - return length in a0
strlen:
    mv a4, a0
    li a0, 0
    lbu a5, 0(a4)
    beqz a5, .strlen_done
.strlen_loop:
    addi a0, a0, 1
    add a5, a4, a0
    lbu a5, 0(a5)
    bnez a5, .strlen_loop
.strlen_done:
    ret

# strncpy(a0, a1, a2) - copy up to a2 bytes from a1 to a0
strncpy:
    li a5, 0                    # count = 0
    beqz a2, .strncpy_done
.strncpy_loop:
    add a4, a1, a5              # src + count
    lbu a4, 0(a4)               # Load byte
    add a3, a0, a5              # dst + count
    sb a4, 0(a3)                # Store byte
    beqz a4, .strncpy_fill      # If null, fill rest
    addi a5, a5, 1              # count++
    bne a2, a5, .strncpy_loop   # If count != max, continue
    j .strncpy_done
.strncpy_fill:
    # Fill rest with zeros
    bgeu a5, a2, .strncpy_done
.strncpy_zero:
    sb zero, 0(a3)
    addi a5, a5, 1
    addi a3, a3, 1
    blt a5, a2, .strncpy_zero
.strncpy_done:
    ret

# print_hex8(a0) - print a0 as 8 hex digits
print_hex8:
    addi sp, sp, -32
    sd ra, 24(sp)
    sd s0, 16(sp)
    sd s1, 8(sp)

    mv s0, a0                   # Value to print
    li s1, 8                    # 8 digits
    addi a0, sp, 0              # Buffer on stack

.ph8_loop:
    srli t0, s0, 60             # Top nibble
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

    # Write the 8 digits
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
str_dot:    .ascii ".\0"
str_slash:  .ascii "/\0"
str_wad:    .ascii "doom1.wad\0"
msg_addr:   .ascii "ADDR:"
msg_buf:    .ascii "BUF: "
newline:    .ascii "\n"
