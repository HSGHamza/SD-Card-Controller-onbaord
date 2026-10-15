/******************************************************************************
 * Step 4: RV32 Core SD Card Reader Test Application
 * File: main_rv32.c
 * Target: Custom RV32 core on Zybo Z7-10 PL
 *
 * Description:
 *   Demonstrates sector reading on a custom RV32 processor by communicating
 *   with the ARM SD server through the AXI Mailbox. Reads Sector 0 (MBR),
 *   validates the partition table signature, parses Partition 1, and reads
 *   the partition's boot sector.
 ******************************************************************************/

#include <stdint.h>
#include <stdio.h>
#include "sd_mailbox.h"

// Adjust this base address to match where the Mailbox is mapped in your RV32 interconnect
#define RV32_MAILBOX_ADDR 0x43C00000U

// Standard MBR Partition Entry Structure (16 bytes)
typedef struct __attribute__((packed)) {
    uint8_t  boot_indicator; // 0x80 = active/bootable, 0x00 = inactive
    uint8_t  start_chs[3];   // Cylinder-Head-Sector start
    uint8_t  partition_type; // e.g. 0x0B/0x0C = FAT32, 0x07 = NTFS/exFAT
    uint8_t  end_chs[3];     // CHS end
    uint32_t starting_lba;   // LBA of first sector in partition
    uint32_t total_sectors;  // Number of sectors in partition
} mbr_partition_entry_t;

static uint8_t sector_buffer[SD_SECTOR_BYTES] __attribute__((aligned(4)));

// Simple print helper (adapt to your RV32 UART print or use printf)
#ifdef HAS_STDIO
#define PRINTF printf
#else
extern void uart_puts(const char *str);
extern void uart_puthex32(uint32_t val);
#define PRINTF(...)
#endif

int main(void)
{
#ifdef HAS_STDIO
    printf("=== RV32 Core MicroSD Sector Reader ===\n");
#endif

    // 1. Initialize SD Mailbox driver
    int res = sd_init(RV32_MAILBOX_ADDR);
    if (res != SD_OK) {
#ifdef HAS_STDIO
        printf("[RV32] Failed to initialize SD mailbox: %s\n", sd_get_error_str(res));
#endif
        return -1;
    }

#ifdef HAS_STDIO
    printf("[RV32] Mailbox connected. Requesting Sector 0 (MBR)...\n");
#endif

    // 2. Read Sector 0 (MBR / Partition Table)
    res = sd_read_sector(0, sector_buffer);
    if (res != SD_OK) {
#ifdef HAS_STDIO
        printf("[RV32] Failed to read Sector 0: %s (HW Error: 0x%08X)\n",
               sd_get_error_str(res), sd_get_last_error());
#endif
        return -1;
    }

#ifdef HAS_STDIO
    printf("[RV32] Sector 0 read successfully!\n");
#endif

    // 3. Check MBR Signature (0x55, 0xAA at offsets 510, 511)
    uint16_t mbr_sig = sector_buffer[510] | ((uint16_t)sector_buffer[511] << 8);
    if (mbr_sig != 0xAA55) {
#ifdef HAS_STDIO
        printf("[RV32] Warning: MBR signature mismatch! Got 0x%04X (expected 0xAA55)\n", mbr_sig);
#endif
        return 1;
    }

#ifdef HAS_STDIO
    printf("[RV32] Valid MBR Signature confirmed: 0xAA55\n");

    // 4. Inspect Partition 1 (Offset 446 in MBR)
    mbr_partition_entry_t *part1 = (mbr_partition_entry_t *)&sector_buffer[446];
    printf("[RV32] Partition 1 info:\n");
    printf("       - Type: 0x%02X\n", part1->partition_type);
    printf("       - Start LBA: %u\n", part1->starting_lba);
    printf("       - Size: %u sectors (~%u MB)\n",
           part1->total_sectors, (part1->total_sectors / 2048));

    // 5. Read the first sector of Partition 1 (e.g. Volume Boot Record)
    if (part1->starting_lba > 0 && part1->partition_type != 0x00) {
        printf("[RV32] Reading Volume Boot Record at LBA %u...\n", part1->starting_lba);
        res = sd_read_sector(part1->starting_lba, sector_buffer);
        if (res == SD_OK) {
            printf("[RV32] VBR read successfully! First 8 bytes: ");
            for (int i = 0; i < 8; i++) {
                printf("%02X ", sector_buffer[i]);
            }
            printf("\n");
        }
    }

    printf("=== RV32 Sector Read Test Completed Successfully! ===\n");
#endif

    return 0;
}

