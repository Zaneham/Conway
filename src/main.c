/* main.c - Portable C entry point for Conway
 *
 * Replaces entry_win.asm (Windows) and main.asm (Linux stub).
 * Does the boring stuff in C -- CLI parsing, file I/O, memory
 * allocation -- then hands off to the assembly translator core
 * which does the interesting stuff. */

#include "conway.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/mman.h>
#endif

/* ---- RISC-V state (passed by pointer to asm core) ---- */
static uint64_t rv_regs[32];       /* x0-x31 */
static uint64_t rv_pc;
static uint64_t rv_fp_regs[32];    /* f0-f31 */

/* ---- Guest memory allocation ---- */

static void *alloc_guest(size_t size)
{
#ifdef _WIN32
    return VirtualAlloc(NULL, size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
#else
    void *p = mmap(NULL, size, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    return (p == MAP_FAILED) ? NULL : p;
#endif
}

/* ---- Make code buffer executable ---- */

static int make_executable(void *addr, size_t size)
{
#ifdef _WIN32
    DWORD old;
    return VirtualProtect(addr, size, PAGE_EXECUTE_READWRITE, &old) ? 0 : -1;
#else
    uintptr_t page = (uintptr_t)addr & ~(uintptr_t)0xFFF;
    size_t len = size + ((uintptr_t)addr - page);
    return mprotect((void *)page, len, PROT_READ | PROT_WRITE | PROT_EXEC);
#endif
}

/* ---- Read entire file into malloc'd buffer ---- */

static void *read_file(const char *path, size_t *out_size)
{
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;

    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    if (len <= 0) { fclose(f); return NULL; }
    fseek(f, 0, SEEK_SET);

    void *buf = malloc((size_t)len);
    if (!buf) { fclose(f); return NULL; }

    size_t nread = fread(buf, 1, (size_t)len, f);
    fclose(f);

    if (nread != (size_t)len) { free(buf); return NULL; }
    *out_size = (size_t)len;
    return buf;
}

/* ---- Banner & usage ---- */

static const char banner[] = "Conway - RISC-V to x86-64 Binary Translator\n";
static const char usage[]  = "Usage: conway [--help] <riscv_elf>\n";

/* ---- Entry point ---- */

int main(int argc, char **argv)
{
    fputs(banner, stdout);
    fflush(stdout);

    /* Parse args */
    const char *elf_path = NULL;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fputs(usage, stdout);
            return 0;
        }
        if (!elf_path) {
            elf_path = argv[i];
        } else {
            fprintf(stderr, "Error: unexpected argument '%s'\n", argv[i]);
            fputs(usage, stderr);
            return 1;
        }
    }
    if (!elf_path) {
        fputs(usage, stderr);
        return 1;
    }

    /* Read ELF file */
    size_t elf_size = 0;
    void *elf_data = read_file(elf_path, &elf_size);
    if (!elf_data) {
        fprintf(stderr, "Error: could not open '%s'\n", elf_path);
        return 2;
    }

    /* Allocate guest memory */
    void *guest = alloc_guest(CONWAY_GUEST_MEM_SIZE);
    if (!guest) {
        fprintf(stderr, "Error: failed to allocate %u MB guest memory\n",
                CONWAY_GUEST_MEM_SIZE / (1024 * 1024));
        free(elf_data);
        return 3;
    }

    /* Platform init (sets up stdout handle for asm syscall layer) */
    plat_init();

    /* Load ELF segments into guest memory */
    int rc = load_elf(elf_data, (uint64_t)elf_size,
                      guest, (uint64_t)CONWAY_GUEST_MEM_SIZE);
    free(elf_data);
    if (rc != 0) {
        fprintf(stderr, "Error: invalid ELF file (loader returned %d)\n", rc);
        return 4;
    }

    /* Init block cache */
    init_block_cache();

    /* Make code buffer executable */
    if (make_executable(code_buffer, CONWAY_CODE_BUF_SIZE) != 0) {
        fprintf(stderr, "Error: failed to make code buffer executable\n");
        return 5;
    }

    /* Zero register file */
    memset(rv_regs, 0, sizeof(rv_regs));
    memset(rv_fp_regs, 0, sizeof(rv_fp_regs));
    rv_pc = 0;

    /* Set stack pointer (x2/sp) = end of guest minus headroom */
    rv_regs[2] = (uint64_t)((char *)guest + CONWAY_GUEST_MEM_SIZE - 4096);

    /* TLS setup (x4/tp) if the ELF has a TLS segment */
    if (elf_tls_memsz != 0) {
        rv_regs[4] = elf_tls_vaddr;
    }

    fprintf(stdout, "ELF loaded, starting execution...\n");

    /* Run the translator */
    execute_blocks(elf_entry_point, guest, rv_regs,
                   &rv_pc, 0, rv_fp_regs);

    /* a0 (x10) is the RISC-V return value */
    return (int)(rv_regs[10] & 0xFF);
}
