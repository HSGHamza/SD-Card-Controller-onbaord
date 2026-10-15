/******************************************************************************
 * Step 1: ARM Cortex-A9 Standalone SD Card Raw Read Test
 * File: xsdps_raw_read.c
 * Target Board: Digilent Zybo Z7-10 (XC7Z010-1CLG400C)
 *
 * Description:
 *   Verifies that the Zynq Processing System (PS) SDIO controller can read
 *   sectors from the onboard microSD card slot (MIO 40-45, CD on MIO 47).
 *   Reads sector 0 (MBR/GPT) using Xilinx standalone driver (XSdPs) in polled
 *   mode and prints a hex dump over UART (115200 baud).
 *
 * Instructions for Vitis:
 *   1. Create Platform Project from your Vivado exported XSA (.xsa).
 *   2. Create Application Project: "sd_raw_test", targeting ps7_cortexa9_0.
 *   3. Replace src/helloworld.c with this file.
 *   4. Connect Zybo Z7 USB cable (PROG/UART) and open serial terminal (115200 8N1).
 *   5. Insert a FAT32 or exFAT formatted microSD card into the Zybo card slot.
 *   6. Run as "Launch Hardware" and verify output in terminal.
 ******************************************************************************/

#include <stdio.h>
#include "xil_printf.h"
#include "xparameters.h"
#include "xsdps.h"
#include "xstatus.h"
#include "xil_cache.h"

#define SD_DEVICE_ID        XPAR_XSDPS_0_DEVICE_ID
#define SECTOR_SIZE         512
#define TARGET_SECTOR_LBA   0

// 512-byte buffer aligned for DMA / Cache coherency
static u8 SectorBuffer[SECTOR_SIZE] __attribute__ ((aligned(32)));
static XSdPs SdInstance;

static void PrintHexDump(const u8 *buf, u32 len)
{
    u32 i, j;
    xil_printf("\r\n--- Hex Dump of Sector %d (512 Bytes) ---\r\n", TARGET_SECTOR_LBA);
    for (i = 0; i < len; i += 16) {
        xil_printf("%04X: ", i);
        // Hex representation
        for (j = 0; j < 16; j++) {
            if (i + j < len) {
                xil_printf("%02X ", buf[i + j]);
            } else {
                xil_printf("   ");
            }
        }
        xil_printf(" | ");
        // Printable ASCII
        for (j = 0; j < 16; j++) {
            if (i + j < len) {
                u8 c = buf[i + j];
                if (c >= 32 && c <= 126) {
                    outbyte(c);
                } else {
                    outbyte('.');
                }
            }
        }
        xil_printf("\r\n");
    }
    xil_printf("--------------------------------------------\r\n");
}

int main(void)
{
    s32 Status;
    XSdPs_Config *SdConfig;

    xil_printf("\r\n===================================================\r\n");
    xil_printf("   Zybo Z7-10 PS SDIO Standalone Sector Read Test   \r\n");
    xil_printf("===================================================\r\n");

    // 1. Look up device configuration
    SdConfig = XSdPs_LookupConfig(SD_DEVICE_ID);
    if (SdConfig == NULL) {
        xil_printf("[ERROR] XSdPs_LookupConfig failed for device %d\r\n", SD_DEVICE_ID);
        return XST_FAILURE;
    }

    // 2. Initialize SD controller instance
    Status = XSdPs_CfgInitialize(&SdInstance, SdConfig, SdConfig->BaseAddress);
    if (Status != XST_SUCCESS) {
        xil_printf("[ERROR] XSdPs_CfgInitialize failed (%d)\r\n", Status);
        return XST_FAILURE;
    }

    // 3. Initialize Card (Identification, clock negotiation, bus width)
    xil_printf("[INFO] Initializing SD Card on PS SDIO 0...\r\n");
    Status = XSdPs_CardInitialize(&SdInstance);
    if (Status != XST_SUCCESS) {
        xil_printf("[ERROR] XSdPs_CardInitialize failed (%d)!\r\n", Status);
        xil_printf("[HINT] Check if microSD card is inserted into J1 slot on Zybo Z7.\r\n");
        xil_printf("[HINT] Verify MIO 40-45 (SDIO) and MIO 47 (CD) in PS configuration.\r\n");
        return XST_FAILURE;
    }

    xil_printf("[SUCCESS] SD Card identified successfully!\r\n");
    xil_printf("          Card Type: %s\r\n",
        (SdInstance.CardType == XSDPS_CARD_SD) ? "Standard SD" :
        (SdInstance.CardType == XSDPS_CARD_MMC) ? "MMC" :
        (SdInstance.CARD_TYPE_SD3 == SdInstance.CardType) ? "SD 3.0" : "SDHC / SDXC");

    // Clear sector buffer
    for (int i = 0; i < SECTOR_SIZE; i++) {
        SectorBuffer[i] = 0;
    }
    Xil_DCacheFlushRange((INTPTR)SectorBuffer, SECTOR_SIZE);

    // 4. Read Sector 0 (Polled read)
    xil_printf("[INFO] Reading Sector LBA %d (512 bytes)...\r\n", TARGET_SECTOR_LBA);
    Status = XSdPs_ReadPolled(&SdInstance, TARGET_SECTOR_LBA, 1, SectorBuffer);
    if (Status != XST_SUCCESS) {
        xil_printf("[ERROR] XSdPs_ReadPolled failed (%d)\r\n", Status);
        return XST_FAILURE;
    }

    Xil_DCacheInvalidateRange((INTPTR)SectorBuffer, SECTOR_SIZE);
    xil_printf("[SUCCESS] Read Sector %d completed successfully!\r\n", TARGET_SECTOR_LBA);

    // Print Hex Dump
    PrintHexDump(SectorBuffer, SECTOR_SIZE);

    // Check MBR signature (offset 510-511: 0x55, 0xAA)
    if (SectorBuffer[510] == 0x55 && SectorBuffer[511] == 0xAA) {
        xil_printf("[PASS] Valid MBR boot signature detected (0x55AA at offset 510-511).\r\n");
        xil_printf("[PASS] STEP 1 VERIFIED: ARM is ready to act as SD server for RV32!\r\n");
    } else {
        xil_printf("[NOTE] Boot signature 0x55AA not found at offset 510 (got %02X %02X).\r\n",
                   SectorBuffer[510], SectorBuffer[511]);
        xil_printf("[INFO] Card may use GPT or unpartitioned RAW filesystem.\r\n");
    }

    return 0;
}

