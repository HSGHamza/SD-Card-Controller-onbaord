#include "sd_mailbox.h"

// Memory barrier macro for RISC-V / GCC
#if defined(__riscv)
#define MEMORY_BARRIER() __asm__ __volatile__ ("fence" ::: "memory")
#else
#define MEMORY_BARRIER() __asm__ __volatile__ ("" ::: "memory")
#endif

#define DEFAULT_TIMEOUT_CYCLES  50000000UL // Adjust based on RV32 clock frequency

static uintptr_t g_mailbox_base = RV32_SD_MAILBOX_BASE;
static uint32_t  g_last_hw_error = 0;

static inline volatile uint32_t* reg_ptr(uint32_t offset)
{
    return (volatile uint32_t*)(g_mailbox_base + offset);
}

static inline uint32_t reg_read(uint32_t offset)
{
    MEMORY_BARRIER();
    uint32_t val = *reg_ptr(offset);
    MEMORY_BARRIER();
    return val;
}

static inline void reg_write(uint32_t offset, uint32_t val)
{
    MEMORY_BARRIER();
    *reg_ptr(offset) = val;
    MEMORY_BARRIER();
}

int sd_init(uintptr_t base_addr)
{
    if (base_addr != 0) {
        g_mailbox_base = base_addr;
    }

    // 1. Verify hardware signature: 0x53444D42 ("SDMB")
    uint32_t sig = reg_read(SD_REG_SIGNATURE);
    if (sig != 0x53444D42U) {
        return SD_ERR_NOT_FOUND;
    }

    // 2. Verify sector size is 512
    uint32_t sec_size = reg_read(SD_REG_SECTOR_SIZE);
    if (sec_size != SD_SECTOR_BYTES) {
        return SD_ERR_HARDWARE;
    }

    // 3. Clear any lingering control/status state
    reg_write(SD_REG_CONTROL, 0);
    reg_write(SD_REG_STATUS, SD_STATUS_IDLE);
    reg_write(SD_REG_ERROR, 0);

    return SD_OK;
}

uint32_t sd_get_last_error(void)
{
    return g_last_hw_error;
}

int sd_read_sector_words(uint32_t sector_lba, uint32_t *dest_words)
{
    if (!dest_words) {
        return SD_ERR_INVALID_ARG;
    }

    // 1. Wait until mailbox is IDLE or DONE from previous transaction
    uint32_t timeout = DEFAULT_TIMEOUT_CYCLES;
    while ((reg_read(SD_REG_STATUS) == SD_STATUS_BUSY) && (--timeout > 0)) {
        // Polling wait
    }
    if (timeout == 0) {
        return SD_ERR_BUSY;
    }

    // 2. Set sector address and command
    reg_write(SD_REG_ADDRESS, sector_lba);
    reg_write(SD_REG_COMMAND, SD_CMD_READ_SECTOR);

    // 3. Trigger request (REQ = 1)
    reg_write(SD_REG_CONTROL, SD_CTRL_REQ);

    // 4. Poll for completion (Wait until STATUS == DONE or ERROR)
    timeout = DEFAULT_TIMEOUT_CYCLES;
    uint32_t status = SD_STATUS_IDLE;
    while (--timeout > 0) {
        status = reg_read(SD_REG_STATUS);
        if (status == SD_STATUS_DONE || status == SD_STATUS_ERROR) {
            break;
        }
    }

    if (timeout == 0) {
        return SD_ERR_TIMEOUT;
    }

    // 5. Check if error occurred on ARM/SD controller
    if (status == SD_STATUS_ERROR) {
        g_last_hw_error = reg_read(SD_REG_ERROR);
        reg_write(SD_REG_STATUS, SD_STATUS_IDLE);
        return SD_ERR_HARDWARE;
    }

    // 6. Copy 128 32-bit words (512 bytes) from Mailbox buffer
    for (uint32_t i = 0; i < SD_SECTOR_WORDS; i++) {
        dest_words[i] = reg_read(SD_REG_DATA + (i * 4));
    }

    // 7. Reset Mailbox status to IDLE
    reg_write(SD_REG_STATUS, SD_STATUS_IDLE);

    return SD_OK;
}

int sd_read_sector(uint32_t sector_lba, uint8_t *dest_buf)
{
    if (!dest_buf) {
        return SD_ERR_INVALID_ARG;
    }

    // Check 4-byte alignment
    if (((uintptr_t)dest_buf & 0x03) == 0) {
        return sd_read_sector_words(sector_lba, (uint32_t*)dest_buf);
    }

    // Unaligned fallback: use aligned temporary stack buffer
    uint32_t temp_words[SD_SECTOR_WORDS];
    int res = sd_read_sector_words(sector_lba, temp_words);
    if (res != SD_OK) {
        return res;
    }

    const uint8_t *src_bytes = (const uint8_t*)temp_words;
    for (uint32_t i = 0; i < SD_SECTOR_BYTES; i++) {
        dest_buf[i] = src_bytes[i];
    }

    return SD_OK;
}

int sd_write_sector(uint32_t sector_lba, const uint8_t *src_buf)
{
    if (!src_buf) {
        return SD_ERR_INVALID_ARG;
    }

    // 1. Wait until mailbox is not BUSY
    uint32_t timeout = DEFAULT_TIMEOUT_CYCLES;
    while ((reg_read(SD_REG_STATUS) == SD_STATUS_BUSY) && (--timeout > 0)) {
    }
    if (timeout == 0) {
        return SD_ERR_BUSY;
    }

    // 2. Copy 512 bytes into Mailbox buffer
    if (((uintptr_t)src_buf & 0x03) == 0) {
        const uint32_t *src_words = (const uint32_t*)src_buf;
        for (uint32_t i = 0; i < SD_SECTOR_WORDS; i++) {
            reg_write(SD_REG_DATA + (i * 4), src_words[i]);
        }
    } else {
        uint32_t temp_words[SD_SECTOR_WORDS];
        uint8_t *dst_bytes = (uint8_t*)temp_words;
        for (uint32_t i = 0; i < SD_SECTOR_BYTES; i++) {
            dst_bytes[i] = src_buf[i];
        }
        for (uint32_t i = 0; i < SD_SECTOR_WORDS; i++) {
            reg_write(SD_REG_DATA + (i * 4), temp_words[i]);
        }
    }

    // 3. Set sector address and write command
    reg_write(SD_REG_ADDRESS, sector_lba);
    reg_write(SD_REG_COMMAND, SD_CMD_WRITE_SECTOR);

    // 4. Trigger request
    reg_write(SD_REG_CONTROL, SD_CTRL_REQ);

    // 5. Wait for completion
    timeout = DEFAULT_TIMEOUT_CYCLES;
    uint32_t status = SD_STATUS_IDLE;
    while (--timeout > 0) {
        status = reg_read(SD_REG_STATUS);
        if (status == SD_STATUS_DONE || status == SD_STATUS_ERROR) {
            break;
        }
    }

    if (timeout == 0) {
        return SD_ERR_TIMEOUT;
    }

    if (status == SD_STATUS_ERROR) {
        g_last_hw_error = reg_read(SD_REG_ERROR);
        reg_write(SD_REG_STATUS, SD_STATUS_IDLE);
        return SD_ERR_HARDWARE;
    }

    reg_write(SD_REG_STATUS, SD_STATUS_IDLE);
    return SD_OK;
}

const char* sd_get_error_str(int err_code)
{
    switch (err_code) {
        case SD_OK:               return "Success";
        case SD_ERR_NOT_FOUND:   return "SD Mailbox peripheral not detected";
        case SD_ERR_TIMEOUT:     return "Operation timed out";
        case SD_ERR_HARDWARE:    return "SD controller hardware error";
        case SD_ERR_BUSY:        return "Mailbox is busy";
        case SD_ERR_INVALID_ARG: return "Invalid argument";
        default:                 return "Unknown error";
    }
}

