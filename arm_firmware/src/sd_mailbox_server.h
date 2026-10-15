#ifndef SD_MAILBOX_SERVER_H
#define SD_MAILBOX_SERVER_H

#include <stdint.h>
#include "xil_types.h"
#include "xparameters.h"

// Base address of the AXI SD Mailbox in Zynq memory map
#ifndef MAILBOX_BASEADDR
#ifdef XPAR_AXI_SD_MAILBOX_0_S_AXI_BASEADDR
#define MAILBOX_BASEADDR  XPAR_AXI_SD_MAILBOX_0_S_AXI_BASEADDR
#else
#define MAILBOX_BASEADDR  0x43C00000U
#endif
#endif

// Register Offsets
#define MAILBOX_REG_COMMAND      0x000U
#define MAILBOX_REG_ADDRESS      0x004U
#define MAILBOX_REG_CONTROL      0x008U
#define MAILBOX_REG_STATUS       0x00CU
#define MAILBOX_REG_ERROR        0x010U
#define MAILBOX_REG_SECTOR_SIZE  0x014U
#define MAILBOX_REG_SIGNATURE    0x018U
#define MAILBOX_REG_DATA         0x020U

// Command definitions
#define MAILBOX_CMD_NOP          0x00U
#define MAILBOX_CMD_READ_SECTOR  0x01U
#define MAILBOX_CMD_WRITE_SECTOR 0x02U

// Status definitions
#define MAILBOX_STATUS_IDLE      0x00U
#define MAILBOX_STATUS_BUSY      0x01U
#define MAILBOX_STATUS_DONE      0x02U
#define MAILBOX_STATUS_ERROR     0x03U

// Control register bit masks
#define MAILBOX_CTRL_REQ         (1U << 0)
#define MAILBOX_CTRL_IRQ_ARM_EN  (1U << 1)
#define MAILBOX_CTRL_IRQ_RV32_EN (1U << 2)

// Error codes
#define MAILBOX_ERR_OK           0x00U
#define MAILBOX_ERR_CARD_INIT    0x01U
#define MAILBOX_ERR_UNKNOWN_CMD  0x02U
#define MAILBOX_ERR_READ_FAIL    0x03U
#define MAILBOX_ERR_WRITE_FAIL   0x04U
#define MAILBOX_ERR_TIMEOUT      0x05U

#define MAILBOX_SIGNATURE_MAGIC  0x53444D42U // "SDMB"
#define SECTOR_SIZE_BYTES        512U
#define SECTOR_SIZE_WORDS        128U

#endif // SD_MAILBOX_SERVER_H

