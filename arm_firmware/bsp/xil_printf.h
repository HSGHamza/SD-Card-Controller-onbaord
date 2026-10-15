/*
 * xil_printf.h — Minimal xil_printf stub
 * Routes xil_printf → printf (UART output via semihosting or newlib).
 */

#ifndef XIL_PRINTF_H
#define XIL_PRINTF_H

#include <stdio.h>

/* Route xil_printf directly to standard printf.
 * In a real BSP this would write to the UART FIFO directly.
 * For standalone builds compiled with arm-none-eabi-gcc + newlib,
 * printf output will go to UART1 if the linker script sets up
 * _write() to write to UART1 TX (see bsp/standalone_uart.c). */
#define xil_printf  printf

#endif /* XIL_PRINTF_H */

