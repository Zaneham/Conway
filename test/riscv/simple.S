# simple.S - Minimal RISC-V test using only RV64I base instructions
# "Keep it simple, stupid" - but said politely, with a cup of tea

.section .text
.global _start

_start:
    # Calculate: 10 + 20 + 30 = 60
    # Using only base integer instructions

    li      a0, 10          # a0 = 10
    li      a1, 20          # a1 = 20
    li      a2, 30          # a2 = 30

    add     a0, a0, a1      # a0 = 10 + 20 = 30
    add     a0, a0, a2      # a0 = 30 + 30 = 60

    # Exit syscall (a7=93, a0=exit code)
    li      a7, 93
    ecall

    # Should never reach here
loop:
    j       loop
