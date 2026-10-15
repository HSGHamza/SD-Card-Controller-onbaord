/*
 * xil_cache.h — Minimal Xilinx data-cache flush/invalidate stubs
 *
 * In a full Vitis BSP these map to CP15 cache-maintenance operations.
 * Here we use GCC ARM inline assembly directly so we compile clean
 * without any BSP library dependency.
 */

#ifndef XIL_CACHE_H
#define XIL_CACHE_H

#include "xil_types.h"

/* Data synchronization barrier helper */
static inline void Xil_DSB(void)
{
    __asm__ volatile ("dsb" ::: "memory");
}

/*
 * Xil_DCacheFlushRange — Write-back and invalidate a virtual address range.
 * Flushes cache lines covering [addr, addr+len).
 * Uses the "clean & invalidate by MVA to PoC" instruction (DCCIMVAC).
 */
static inline void Xil_DCacheFlushRange(INTPTR addr, u32 len)
{
    INTPTR end = addr + (INTPTR)len;
    INTPTR aligned = addr & ~(INTPTR)31;  /* 32-byte cache line */

    for (; aligned < end; aligned += 32) {
        __asm__ volatile (
            "mcr p15, 0, %0, c7, c14, 1"  /* DCCIMVAC */
            : : "r"(aligned) : "memory"
        );
    }
    Xil_DSB();
}

/*
 * Xil_DCacheInvalidateRange — Invalidate (discard) a virtual address range.
 * Uses "invalidate by MVA to PoC" (DCIMVAC).
 * WARNING: Only use when the range is NOT dirty (e.g. after DMA fills it).
 */
static inline void Xil_DCacheInvalidateRange(INTPTR addr, u32 len)
{
    INTPTR end = addr + (INTPTR)len;
    INTPTR aligned = addr & ~(INTPTR)31;

    for (; aligned < end; aligned += 32) {
        __asm__ volatile (
            "mcr p15, 0, %0, c7, c6, 1"   /* DCIMVAC */
            : : "r"(aligned) : "memory"
        );
    }
    Xil_DSB();
}

#endif /* XIL_CACHE_H */

