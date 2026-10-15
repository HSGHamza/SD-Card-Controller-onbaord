#ifndef RV32_SD_MAILBOX_H
#define RV32_SD_MAILBOX_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Default base address (Adjust to match your RV32 AXI address map)
#ifndef RV32_SD_MAILBOX_BASE
#define RV32_SD_MAILBOX_BASE  0x43C00000U
#endif

// Register Offsets
#define SD_REG_COMMAND      0x000U
#define SD_REG_ADDRESS      0x004U
#define SD_REG_CONTROL      0x008U
#define SD_REG_STATUS       0x00CU
#define SD_REG_ERROR        0x010U
#define SD_REG_SECTOR_SIZE  0x014U
#define SD_REG_SIGNATURE    0x018U
#define SD_REG_DATA         0x020U

// Command codes
#define SD_CMD_NOP          0x00U
#define SD_CMD_READ_SECTOR  0x01U
#define SD_CMD_WRITE_SECTOR 0x02U

// Status register values
#define SD_STATUS_IDLE      0x00U
#define SD_STATUS_BUSY      0x01U
#define SD_STATUS_DONE      0x02U
#define SD_STATUS_ERROR     0x03U

// Control register bits
#define SD_CTRL_REQ         (1U << 0)
#define SD_CTRL_IRQ_ARM_EN  (1U << 1)
#define SD_CTRL_IRQ_RV32_EN (1U << 2)

// Return error codes
#define SD_OK               0
#define SD_ERR_NOT_FOUND   -1
#define SD_ERR_TIMEOUT     -2
#define SD_ERR_HARDWARE    -3
#define SD_ERR_BUSY        -4
#define SD_ERR_INVALID_ARG -5

#define SD_SECTOR_BYTES     512U
#define SD_SECTOR_WORDS     128U

/**
 * Initialize the SD Mailbox driver and verify peripheral presence.
 * @param base_addr Physical base address of the Mailbox in RV32 memory space.
 * @return SD_OK on success, negative error code on failure.
 */
int sd_init(uintptr_t base_addr);

/**
 * Read a 512-byte sector from the SD card into a destination byte buffer.
 * @param sector_lba Logical Block Address (0, 1, 2, ...)
 * @param dest_buf Pointer to 512-byte buffer in RV32 memory
 * @return SD_OK on success, negative error code on failure.
 */
int sd_read_sector(uint32_t sector_lba, uint8_t *dest_buf);

/**
 * Read a 512-byte sector from the SD card directly as 128 32-bit words.
 * (Faster on RV32 as it avoids byte-by-byte copies).
 * @param sector_lba Logical Block Address
 * @param dest_words Pointer to 128 uint32_t array (512 bytes, 4-byte aligned)
 * @return SD_OK on success, negative error code on failure.
 */
int sd_read_sector_words(uint32_t sector_lba, uint32_t *dest_words);

/**
 * Write a 512-byte sector from RV32 memory to the SD card.
 * @param sector_lba Logical Block Address
 * @param src_buf Pointer to 512-byte buffer in RV32 memory
 * @return SD_OK on success, negative error code on failure.
 */
int sd_write_sector(uint32_t sector_lba, const uint8_t *src_buf);

/**
 * Retrieve the last hardware error code reported by ARM/Mailbox.
 */
uint32_t sd_get_last_error(void);

/**
 * Convert return code to human-readable string.
 */
const char* sd_get_error_str(int err_code);

#ifdef __cplusplus
}
#endif

#endif // RV32_SD_MAILBOX_H

