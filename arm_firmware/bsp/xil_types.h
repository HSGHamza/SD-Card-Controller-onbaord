/*
 * xil_types.h — Minimal Xilinx standalone type definitions
 * These replace the Vitis BSP types so we can compile with arm-none-eabi-gcc.
 */

#ifndef XIL_TYPES_H
#define XIL_TYPES_H

#include <stdint.h>

typedef uint8_t   u8;
typedef uint16_t  u16;
typedef uint32_t  u32;
typedef uint64_t  u64;

typedef int8_t    s8;
typedef int16_t   s16;
typedef int32_t   s32;
typedef int64_t   s64;

typedef uintptr_t INTPTR;
typedef uintptr_t UINTPTR;
typedef uint32_t  XSECURE_ATTRIBUTE_PACKED;

typedef int XStatus;

#ifndef TRUE
#define TRUE  1
#endif
#ifndef FALSE
#define FALSE 0
#endif
#ifndef NULL
#define NULL ((void*)0)
#endif

#define XST_SUCCESS  0
#define XST_FAILURE  1

#endif /* XIL_TYPES_H */

