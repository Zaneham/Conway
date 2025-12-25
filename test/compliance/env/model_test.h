// Conway model_test.h - RISC-V Compliance Test Environment
// Adapts riscv-arch-test suite for Conway binary translator

#ifndef _CONWAY_MODEL_TEST_H
#define _CONWAY_MODEL_TEST_H

// Conway uses Linux syscall convention for exit:
// a0 = exit code, a7 = 93 (exit syscall)
#define RVMODEL_HALT                    \
    li a7, 93;                          \
    ecall;                              \
1:  j 1b;

// Boot sequence - nothing special needed
#define RVMODEL_BOOT

// Data section markers for signature
#define RVMODEL_DATA_SECTION

#define RVMODEL_DATA_BEGIN              \
    .align 4;                           \
    .global begin_signature;            \
begin_signature:

#define RVMODEL_DATA_END                \
    .align 4;                           \
    .global end_signature;              \
end_signature:

// I/O stubs - Conway doesn't have debug I/O
#define RVMODEL_IO_INIT
#define RVMODEL_IO_WRITE_STR(_R, _STR)
#define RVMODEL_IO_CHECK()
#define RVMODEL_IO_ASSERT_GPR_EQ(_S, _R, _I)
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)

// Interrupt stubs - Conway runs in user mode only
#define RVMODEL_SET_MSW_INT
#define RVMODEL_CLEAR_MSW_INT
#define RVMODEL_CLEAR_MTIMER_INT
#define RVMODEL_CLEAR_MEXT_INT

// PMP configuration (not used by Conway)
#ifndef RVMODEL_PMP_GRAIN
  #define RVMODEL_PMP_GRAIN   0
#endif

#ifndef RVMODEL_NUM_PMPS
  #define RVMODEL_NUM_PMPS    0
#endif

#endif // _CONWAY_MODEL_TEST_H
