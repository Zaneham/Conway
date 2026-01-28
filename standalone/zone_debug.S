# zone_debug.S - Debug test for zone allocator pattern
# Tests LUI, memory operations, and values Doom uses

.section .text
.global _start

_start:
    # Set up stack
    li sp, 0x6FFFF0

    # Test 1: LUI with 0x600 (should give 0x600000)
    lui a0, 0x600           # a0 = 0x600000

    # Store result at 0x100
    li t0, 0x100
    sd a0, 0(t0)            # Store 0x600000 at addr 0x100

    # Test 2: LUI with negative upper bits
    lui a1, 0x69000         # Upper 20 bits for gp calculation

    # Store at 0x108
    li t0, 0x108
    sd a1, 0(t0)

    # Test 3: Small constant
    li a2, 6                # Just the number 6
    li t0, 0x110
    sd a2, 0(t0)

    # Test 4: Another way to load 0x600000
    li a3, 0x600000
    li t0, 0x118
    sd a3, 0(t0)

    # Test 5: Simulate heap_ptr pattern
    # heap_ptr is typically at a gp-relative address
    # Let's store a value and load it back
    li t1, 0x1000           # Use 0x1000 as our "heap_ptr" location
    li t2, 0x69568          # Initial heap value
    sd t2, 0(t1)            # Store heap_ptr = 0x69568

    # Now load it back like malloc would
    ld a4, 0(t1)            # Load heap_ptr into a4

    # Store the loaded value for verification
    li t0, 0x120
    sd a4, 0(t0)

    # Test 6: Test LW (32-bit load with sign extension)
    li t0, 0x200
    li t1, 0x600000
    sw t1, 0(t0)            # Store 0x600000 as 32-bit
    lw a5, 0(t0)            # Load back with LW
    li t0, 0x128
    sd a5, 0(t0)            # Store for verification

    # Exit with value at 0x100 shifted right to verify
    ld a0, 0x100(zero)
    srli a0, a0, 20         # Should give 6 if value was 0x600000

    # Exit
    li a7, 93               # exit syscall
    ecall
