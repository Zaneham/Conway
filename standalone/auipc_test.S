# auipc_test.S - Test AUIPC instruction

.section .text
.global _start

_start:
    # Test AUIPC: result should be PC + (imm << 12)
    # At address 0x1000, auipc with imm=1 should give 0x1000 + 0x1000 = 0x2000

test1:
    auipc t0, 1             # t0 = PC + 0x1000
    # Calculate expected value: PC of this instruction + 0x1000
    # The instruction is at 0x1000, so t0 should be 0x2000

    # Check by subtracting expected value
    li t1, 0x2000
    bne t0, t1, fail1

test2:
    # Test with larger immediate
    auipc t0, 0x10          # t0 = PC + 0x10000
    # PC of this auipc instruction depends on previous code size
    # Let's compute relative to a known label instead

test3:
    # Use the actual doom pattern: auipc then addi
    # Simulate: auipc gp, 0x59; addi gp, gp, -744
    # At PC=0x1000 + offset, gp = PC + 0x59000 - 744

    # Get current PC
here:
    auipc t2, 0             # t2 = PC of this instruction
    addi t3, t2, 4          # t3 = PC + 4 (next instruction)

    # Verify t2 matches label address
    la t4, here
    bne t2, t4, fail3

    # Success
    li a0, 0
    li a7, 93
    ecall

fail1:
    li a0, 81
    li a7, 93
    ecall

fail3:
    li a0, 83
    li a7, 93
    ecall
