/******************************************************************************
 * Step 3: ARM Cortex-A9 Mailbox SD Card Server
 * File: sd_mailbox_server.c
 * Target Board: Digilent Zybo Z7-10 (XC7Z010-1CLG400C)
 *
 * Description:
 *   Continuously monitors the AXI SD Mailbox in PL for sector read/write
 *   requests from the RV32 core. When a request arrives, the ARM accesses
 *   the onboard microSD card through PS SDIO 0 (XSdPs), transfers the sector
 *   to/from the mailbox buffer, and signals completion to the RV32.
 ******************************************************************************/

#include <stdio.h>
#include <stdbool.h>
#include "xil_printf.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xparameters.h"
#include "xsdps.h"
#include "sd_mailbox_server.h"

#define SD_DEVICE_ID XPAR_XSDPS_0_DEVICE_ID

// Static buffers
static u8 SectorBuffer[SECTOR_SIZE_BYTES] __attribute__ ((aligned(32)));
static XSdPs SdInstance;

// Mailbox Register Access Helpers
static inline u32 MailboxReadReg(u32 offset)
{
    return Xil_In32(MAILBOX_BASEADDR + offset);
}

static inline void MailboxWriteReg(u32 offset, u32 val)
{
    Xil_Out32(MAILBOX_BASEADDR + offset, val);
}

// Check if RV32 has raised a request
static inline bool MailboxRequestPending(void)
{
    u32 ctrl = MailboxReadReg(MAILBOX_REG_CONTROL);
    return (ctrl & MAILBOX_CTRL_REQ) != 0;
}

// Copy 512-byte sector buffer from memory into Mailbox buffer
static void MailboxWriteDataBuffer(const u8 *buf)
{
    const u32 *words = (const u32 *)buf;
    for (u32 i = 0; i < SECTOR_SIZE_WORDS; i++) {
        MailboxWriteReg(MAILBOX_REG_DATA + (i * 4), words[i]);
    }
}

// Copy 512-byte sector buffer from Mailbox buffer into memory
static void MailboxReadDataBuffer(u8 *buf)
{
    u32 *words = (u32 *)buf;
    for (u32 i = 0; i < SECTOR_SIZE_WORDS; i++) {
        words[i] = MailboxReadReg(MAILBOX_REG_DATA + (i * 4));
    }
}

// Initialize SD Card
static int InitSdCard(void)
{
    s32 status;
    XSdPs_Config *sd_config;

    sd_config = XSdPs_LookupConfig(SD_DEVICE_ID);
    if (!sd_config) {
        xil_printf("[ARM-SD] Error: SD config lookup failed\r\n");
        return -1;
    }

    status = XSdPs_CfgInitialize(&SdInstance, sd_config, sd_config->BaseAddress);
    if (status != XST_SUCCESS) {
        xil_printf("[ARM-SD] Error: SD cfg init failed (%d)\r\n", status);
        return -1;
    }

    status = XSdPs_CardInitialize(&SdInstance);
    if (status != XST_SUCCESS) {
        xil_printf("[ARM-SD] Error: Card initialize failed (%d)\r\n", status);
        return -1;
    }

    xil_printf("[ARM-SD] SD card initialized and ready.\r\n");
    return 0;
}

int main(void)
{
    xil_printf("\r\n=======================================================\r\n");
    xil_printf("   Zybo Z7-10 ARM Cortex-A9 <-> RV32 SD Mailbox Server  \r\n");
    xil_printf("=======================================================\r\n");

    // 1. Probe Mailbox IP in PL
    xil_printf("[ARM-SD] Checking AXI SD Mailbox at 0x%08X...\r\n", MAILBOX_BASEADDR);
    u32 signature = MailboxReadReg(MAILBOX_REG_SIGNATURE);
    if (signature != MAILBOX_SIGNATURE_MAGIC) {
        xil_printf("[ARM-SD] ERROR: Invalid Mailbox signature! Expected 0x%08X, got 0x%08X\r\n",
                   MAILBOX_SIGNATURE_MAGIC, signature);
        xil_printf("[ARM-SD] Ensure Bitstream is loaded and AXI base address matches.\r\n");
        return -1;
    }

    u32 sector_size = MailboxReadReg(MAILBOX_REG_SECTOR_SIZE);
    xil_printf("[ARM-SD] Mailbox verified! Hardware reports sector size: %d bytes\r\n", sector_size);

    // 2. Initialize SD Card
    if (InitSdCard() != 0) {
        MailboxWriteReg(MAILBOX_REG_ERROR, MAILBOX_ERR_CARD_INIT);
        MailboxWriteReg(MAILBOX_REG_STATUS, MAILBOX_STATUS_ERROR);
        xil_printf("[ARM-SD] Fatal: SD card not available.\r\n");
        return -1;
    }

    // Initialize Mailbox state to IDLE
    MailboxWriteReg(MAILBOX_REG_STATUS, MAILBOX_STATUS_IDLE);
    MailboxWriteReg(MAILBOX_REG_ERROR, MAILBOX_ERR_OK);

    xil_printf("[ARM-SD] Server running. Listening for RV32 sector requests...\r\n");

    u32 req_count = 0;

    // 3. Main Request Handling Loop
    for (;;) {
        if (MailboxRequestPending()) {
            req_count++;
            u32 command = MailboxReadReg(MAILBOX_REG_COMMAND);
            u32 sector  = MailboxReadReg(MAILBOX_REG_ADDRESS);

            // Set STATUS to BUSY and clear REQ bit
            MailboxWriteReg(MAILBOX_REG_STATUS, MAILBOX_STATUS_BUSY);
            u32 ctrl = MailboxReadReg(MAILBOX_REG_CONTROL);
            MailboxWriteReg(MAILBOX_REG_CONTROL, ctrl & ~MAILBOX_CTRL_REQ);

            xil_printf("[ARM-SD] Req #%d: Cmd=%d, LBA=%d ... ", req_count, command, sector);

            if (command == MAILBOX_CMD_READ_SECTOR) {
                // Read Sector from SD card
                s32 status = XSdPs_ReadPolled(&SdInstance, sector, 1, SectorBuffer);
                if (status == XST_SUCCESS) {
                    Xil_DCacheInvalidateRange((INTPTR)SectorBuffer, SECTOR_SIZE_BYTES);
                    // Copy to Mailbox buffer for RV32
                    MailboxWriteDataBuffer(SectorBuffer);
                    MailboxWriteReg(MAILBOX_REG_ERROR, MAILBOX_ERR_OK);
                    MailboxWriteReg(MAILBOX_REG_STATUS, MAILBOX_STATUS_DONE);
                    xil_printf("DONE [OK]\r\n");
                } else {
                    xil_printf("FAIL (status %d)\r\n", status);
                    MailboxWriteReg(MAILBOX_REG_ERROR, MAILBOX_ERR_READ_FAIL);
                    MailboxWriteReg(MAILBOX_REG_STATUS, MAILBOX_STATUS_ERROR);
                }
            } else if (command == MAILBOX_CMD_WRITE_SECTOR) {
                // Read data from Mailbox buffer into local memory
                MailboxReadDataBuffer(SectorBuffer);
                Xil_DCacheFlushRange((INTPTR)SectorBuffer, SECTOR_SIZE_BYTES);

                // Write Sector to SD card
                s32 status = XSdPs_WritePolled(&SdInstance, sector, 1, SectorBuffer);
                if (status == XST_SUCCESS) {
                    MailboxWriteReg(MAILBOX_REG_ERROR, MAILBOX_ERR_OK);
                    MailboxWriteReg(MAILBOX_REG_STATUS, MAILBOX_STATUS_DONE);
                    xil_printf("WRITE DONE [OK]\r\n");
                } else {
                    xil_printf("WRITE FAIL (status %d)\r\n", status);
                    MailboxWriteReg(MAILBOX_REG_ERROR, MAILBOX_ERR_WRITE_FAIL);
                    MailboxWriteReg(MAILBOX_REG_STATUS, MAILBOX_STATUS_ERROR);
                }
            } else {
                xil_printf("UNKNOWN CMD (%d)\r\n", command);
                MailboxWriteReg(MAILBOX_REG_ERROR, MAILBOX_ERR_UNKNOWN_CMD);
                MailboxWriteReg(MAILBOX_REG_STATUS, MAILBOX_STATUS_ERROR);
            }
        }
    }

    return 0;
}

