// Conway model_test.h - RISC-V to x86-64 Binary Translator
// Environment macros for riscv-arch-test compliance suite

#ifndef _CONWAY_MODEL_TEST_H
#define _CONWAY_MODEL_TEST_H

#define XLEN 64
#define ALIGNMENT 3
#define FLEN 64

// Conway doesn't implement PMP
#define RVMODEL_PMP_GRAIN   0
#define RVMODEL_NUM_PMPS    0

// Boot code - set up stack pointer
#define RVMODEL_BOOT        \
    la sp, _stack_top;

// Halt - use ECALL with exit syscall
// a0 = exit code (0 = success)
// a7 = syscall number (93 = exit)
#define RVMODEL_HALT        \
    li a0, 0;               \
    li a7, 93;              \
    ecall;

// Data section with signature markers
#define RVMODEL_DATA_BEGIN  \
    .align ALIGNMENT;       \
    .global begin_signature; begin_signature:

#define RVMODEL_DATA_END    \
    .align ALIGNMENT;       \
    .global end_signature; end_signature:

// I/O macros - Conway doesn't have debug I/O
#define RVMODEL_IO_INIT
#define RVMODEL_IO_WRITE_STR(_R, _STR)
#define RVMODEL_IO_CHECK()
#define RVMODEL_IO_ASSERT_GPR_EQ(_S, _R, _I)
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)

// Interrupt macros - not implemented
#define RVMODEL_SET_MSW_INT
#define RVMODEL_CLEAR_MSW_INT
#define RVMODEL_CLEAR_MTIMER_INT
#define RVMODEL_CLEAR_MEXT_INT

#endif // _CONWAY_MODEL_TEST_H
