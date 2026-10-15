/*
 * xil_io.h — Minimal Xilinx standalone I/O macros
 * Replaces the Vitis BSP xil_io.h for arm-none-eabi-gcc cross-compilation.
 * Uses standard C volatile pointer dereferencing for MMIO.
 */

#ifndef XIL_IO_H
#define XIL_IO_H

#include "xil_types.h"

/* MMIO 32-bit read */
static inline u32 Xil_In32(UINTPTR addr)
{
    return *((volatile u32 *)(addr));
}

/* MMIO 32-bit write */
static inline void Xil_Out32(UINTPTR addr, u32 val)
{
    *((volatile u32 *)(addr)) = val;
}

/* MMIO 8-bit read */
static inline u8 Xil_In8(UINTPTR addr)
{
    return *((volatile u8 *)(addr));
}

/* MMIO 8-bit write */
static inline void Xil_Out8(UINTPTR addr, u8 val)
{
    *((volatile u8 *)(addr)) = val;
}

#endif /* XIL_IO_H */

