/* Conway linker script for arch tests */
OUTPUT_FORMAT("elf64-littleriscv")
OUTPUT_ARCH(riscv)
ENTRY(rvtest_entry_point)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x1000, LENGTH = 2M
}

SECTIONS
{
    . = 0x1000;

    .text : {
        *(.text.init)
        *(.text)
        *(.text.*)
    } > RAM

    .data : {
        *(.data)
        *(.data.*)
        *(.rodata)
        *(.rodata.*)
        *(.sdata)
        *(.sdata.*)
    } > RAM

    .bss : {
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
    } > RAM

    /* Signature section */
    .signature : {
        *(.signature)
    } > RAM

    /* Stack at end of RAM */
    . = ALIGN(16);
    _stack_bottom = .;
    . = . + 4K;
    _stack_top = .;
}
