# Standalone C Extension Tests for Conway
# Tests compressed (16-bit) instructions

.section .text
.global _start
.option rvc   # Enable compressed instructions

_start:
    # ============ C.LI (Load Immediate) ============
    c.li    a0, 31              # Load small immediate
    li      t0, 31
    bne     a0, t0, fail

    c.li    a1, -5              # Load negative immediate
    li      t0, -5
    bne     a1, t0, fail

    # ============ C.MV (Move) ============
    li      a0, 42
    c.mv    a1, a0
    li      t0, 42
    bne     a1, t0, fail

    # ============ C.ADD ============
    li      a0, 20
    li      a1, 22
    c.add   a0, a1              # a0 = a0 + a1 = 42
    li      t0, 42
    bne     a0, t0, fail

    # ============ C.ADDI ============
    li      a0, 35
    c.addi  a0, 7               # a0 = a0 + 7 = 42
    li      t0, 42
    bne     a0, t0, fail

    # ============ C.SLLI ============
    li      a0, 1
    c.slli  a0, 5               # a0 = 1 << 5 = 32
    li      t0, 32
    bne     a0, t0, fail

    # ============ C.SRLI (uses s0-s7 or a0-a7) ============
    li      s0, 256
    c.srli  s0, 4               # s0 = 256 >> 4 = 16
    li      t0, 16
    bne     s0, t0, fail

    # ============ C.SRAI ============
    li      s1, -128
    c.srai  s1, 3               # s1 = -128 >> 3 = -16 (arithmetic)
    li      t0, -16
    bne     s1, t0, fail

    # ============ C.ANDI ============
    li      s0, 0xFF
    c.andi  s0, 0x0F            # s0 = 0xFF & 0x0F = 0x0F
    li      t0, 0x0F
    bne     s0, t0, fail

    # ============ C.SUB ============
    li      s0, 50
    li      s1, 8
    c.sub   s0, s1              # s0 = 50 - 8 = 42
    li      t0, 42
    bne     s0, t0, fail

    # ============ C.XOR ============
    li      s0, 0xFF
    li      s1, 0x0F
    c.xor   s0, s1              # s0 = 0xFF ^ 0x0F = 0xF0
    li      t0, 0xF0
    bne     s0, t0, fail

    # ============ C.OR ============
    li      s0, 0xF0
    li      s1, 0x0F
    c.or    s0, s1              # s0 = 0xF0 | 0x0F = 0xFF
    li      t0, 0xFF
    bne     s0, t0, fail

    # ============ C.AND ============
    li      s0, 0xFF
    li      s1, 0x3C
    c.and   s0, s1              # s0 = 0xFF & 0x3C = 0x3C
    li      t0, 0x3C
    bne     s0, t0, fail

    # ============ C.J (unconditional jump) ============
    c.j     cj_target
    j       fail
cj_target:

    # ============ C.BEQZ ============
    li      s0, 0
    c.beqz  s0, cbeqz_pass
    j       fail
cbeqz_pass:

    # ============ C.BNEZ ============
    li      s0, 42
    c.bnez  s0, cbnez_pass
    j       fail
cbnez_pass:

    # ============ C.ADDIW (32-bit add immediate) ============
    li      a0, 35
    c.addiw a0, 7               # 32-bit add, sign extended
    li      t0, 42
    bne     a0, t0, fail

    # ============ C.NOP ============
    c.nop                       # Should do nothing

    # All tests passed
    li      a0, 0
    li      a7, 93
    ecall

fail:
    li      a0, 1
    li      a7, 93
    ecall
