/*
 * startup.c — Minimal ARM Cortex-A9 Standalone Startup Code
 *
 * Sets up:
 *   1. Stack pointer for supervisor (SVC) mode
 *   2. UART1 for xil_printf / printf output (newlib _write hook)
 *   3. Branches to main()
 *
 * This replaces the Xilinx standalone BSP asm_vectors.S + boot.S.
 * It runs in Supervisor (SVC) mode, which is what a standalone A9 uses
 * when it boots from FSBL → Application.
 *
 * Target: Zynq-7000 Cortex-A9 (ARMv7-A), ARM mode (not Thumb)
 */

#include <stdint.h>

/* ---- UART1 register base (MIO 48-49) ---- */
#define UART1_BASE  0xE0001000U
#define UART1_FIFO  (*(volatile uint32_t *)(UART1_BASE + 0x030U))
#define UART1_SR    (*(volatile uint32_t *)(UART1_BASE + 0x02CU))
#define UART1_SR_TXEMPTY  (1U << 3)
#define UART1_SR_TXFULL   (1U << 4)

/* ---- newlib _write: routes printf to UART1 TX ---- */
int _write(int fd, const char *buf, int count)
{
    (void)fd;
    for (int i = 0; i < count; i++) {
        /* Wait until TX FIFO not full */
        while (UART1_SR & UART1_SR_TXFULL) {}
        UART1_FIFO = (uint32_t)(unsigned char)buf[i];
    }
    return count;
}

/* Newlib stubs to satisfy linker */
int  _read(int fd, char *buf, int count) { (void)fd; (void)buf; (void)count; return 0; }
int  _close(int fd) { (void)fd; return -1; }
int  _lseek(int fd, int offset, int whence) { (void)fd; (void)offset; (void)whence; return -1; }
int  _fstat(int fd, void *st) { (void)fd; (void)st; return 0; }
int  _isatty(int fd) { (void)fd; return 1; }
void _exit(int code) { (void)code; while(1); }
void *_sbrk(int incr) { (void)incr; return (void*)-1; } /* no heap */

/* ---- External main() ---- */
extern int main(void);

/* ---- BSS section symbols (set by linker script) ---- */
extern uint32_t __bss_start__;
extern uint32_t __bss_end__;

/* ---- reset_handler: C entry point from FSBL → Application ---- */
__attribute__((naked, noreturn, section(".text.reset")))
void reset_handler(void)
{
    /* Set up SVC mode stack — linker script places _stack_top at top of OCM */
    extern uint32_t _stack_top;
    __asm__ volatile (
        "ldr sp, =_stack_top   \n"
        "cpsid if              \n"  /* disable IRQ + FIQ */
        ::: "memory"
    );

    /* Zero-fill BSS */
    uint32_t *bss = &__bss_start__;
    uint32_t *bss_end = &__bss_end__;
    while (bss < bss_end) { *bss++ = 0U; }

    /* Call main() */
    main();

    /* Should never return */
    for (;;) {}
}

