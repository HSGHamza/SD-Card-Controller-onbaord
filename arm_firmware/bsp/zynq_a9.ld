/*
 * zynq_a9.ld — Linker Script for Zynq-7000 ARM Cortex-A9 Standalone
 *
 * Memory layout (Zybo Z7-10 with 512MB DDR3):
 *   - OCM:   0x00000000 - 0x0002FFFF (192 KB on-chip memory, always mapped)
 *   - DDR:   0x00100000 - 0x1FFFFFFF (511 MB DRAM)
 *
 * We place the application in OCM so it runs without DDR initialization.
 * The FSBL (First Stage Boot Loader) will copy our ELF from QSPI flash to
 * OCM then jump to the entry point before DDR is even trained.
 *
 * Stack: grows downward from the top of OCM (0x0002FFFC).
 *
 * Note: If your application grows > ~180 KB, move .text to DDR at 0x00100000.
 * The FSBL already initializes DDR before loading the second stage image.
 */

OUTPUT_FORMAT("elf32-littlearm")
OUTPUT_ARCH(arm)
ENTRY(reset_handler)

MEMORY
{
    /* On-chip RAM: safe to run from without any DDR init */
    OCM (rwx) : ORIGIN = 0x00000000, LENGTH = 192K

    /* DDR SDRAM: available after FSBL initializes PS DRAM controller */
    /* Uncomment and update MEMORY/SECTIONS if app grows beyond OCM   */
    /* DDR (rwx) : ORIGIN = 0x00100000, LENGTH = 511M               */
}

/* Stack pointer initial value — placed at top of OCM */
_stack_top = ORIGIN(OCM) + LENGTH(OCM) - 4;

SECTIONS
{
    /* ---- Interrupt Vector Table (must be at 0x0000_0000 for VBAR) ---- */
    .vectors :
    {
        KEEP(*(.text.vectors))
        KEEP(*(.text.reset))
    } > OCM

    /* ---- Code ---- */
    .text :
    {
        *(.text.*)
        *(.text)
        *(.rodata)
        *(.rodata.*)
    } > OCM

    /* ---- Read-only data ---- */
    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    } > OCM

    /* ---- Initialized data (copied from ROM by startup) ---- */
    .data :
    {
        *(.data)
        *(.data.*)
    } > OCM

    /* ---- Uninitialized data (zeroed by startup.c) ---- */
    .bss :
    {
        __bss_start__ = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        __bss_end__ = .;
    } > OCM

    /* ---- Stack (conceptual; actual value set at top of OCM) ---- */
    .stack (NOLOAD) :
    {
        . = ALIGN(8);
        _stack_bottom = .;
        . += 16K;   /* 16 KB stack */
        _stack_top_sym = .;
    } > OCM

    /* ---- Discard debug/exception tables ---- */
    /DISCARD/ :
    {
        *(.ARM.exidx*)
        *(.ARM.extab*)
        *(.eh_frame*)
    }
}

