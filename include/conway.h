/* conway.h - C interface to the assembly core
 *
 * Declares every symbol the C entry point needs from the NASM modules.
 * The core translator uses SysV ABI on all platforms (including Windows),
 * so we slap __attribute__((sysv_abi)) on those declarations when
 * building with MinGW. Platform functions use MS x64 ABI everywhere,
 * but we don't call them from C -- we do memory protection ourselves. */

#ifndef CONWAY_H
#define CONWAY_H

#include <stdint.h>

/* ---- Sizes (must match translator.asm / entry_win.asm) ---- */
#define CONWAY_CODE_BUF_SIZE   16777216     /* 16 MB */
#define CONWAY_GUEST_MEM_SIZE  0x10000000   /* 256 MB */

/* ---- Calling convention ---- */
#ifdef _WIN32
#define CONWAY_SYSV __attribute__((sysv_abi))
#else
#define CONWAY_SYSV
#endif

/* ---- Platform (platform_win.asm / platform_linux.asm) ---- */
extern void plat_init(void);

/* ---- ELF Loader (elf_loader.asm) ---- */
CONWAY_SYSV extern int load_elf(const void *data, uint64_t size,
                                void *guest, uint64_t guest_size);

extern uint64_t elf_entry_point;
extern uint64_t elf_load_base;
extern uint64_t elf_brk_base;
extern uint64_t elf_tls_memsz;
extern uint64_t elf_tls_filesz;
extern uint64_t elf_tls_vaddr;

/* ---- Translator (translator.asm) ---- */
extern void init_block_cache(void);

CONWAY_SYSV extern uint64_t execute_blocks(
    uint64_t pc, void *guest, uint64_t *regs,
    uint64_t *pc_ptr, uint64_t max_blocks, uint64_t *fp_regs);

extern char code_buffer[];

#endif /* CONWAY_H */
