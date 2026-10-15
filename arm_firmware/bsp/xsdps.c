/*
 * xsdps.c — Minimal Zynq-7000 PS SDIO SD Card Driver
 *
 * Self-contained implementation for arm-none-eabi-gcc (no Vitis BSP needed).
 * Implements polled-mode SD/SDHC card initialization and block read/write
 * through the Zynq-7000 PS SDIO controller (eSDHC compatible).
 *
 * Target: Zybo Z7-10 (XC7Z010), SDIO0 on MIO 40-45, 3.3V, 4-bit bus.
 *
 * References:
 *   - Zynq-7000 TRM (UG585) Chapter 18: SD/SDIO/eMMC
 *   - SD Physical Layer Spec v4.10
 *   - Xilinx embeddedsw sdps driver (Apache-2.0)
 */

#include "xsdps.h"
#include "xil_io.h"
#include "xil_printf.h"

/* ---- Private MMIO helpers (byte-width for SD controller registers) ---- */

static inline u32 SdRd32(u32 base, u32 off)
{
    return Xil_In32((UINTPTR)(base + off));
}

static inline void SdWr32(u32 base, u32 off, u32 val)
{
    Xil_Out32((UINTPTR)(base + off), val);
}

static inline u16 SdRd16(u32 base, u32 off)
{
    return (u16)((*((volatile u16 *)(uintptr_t)(base + off))));
}

static inline void SdWr16(u32 base, u32 off, u16 val)
{
    *((volatile u16 *)(uintptr_t)(base + off)) = val;
}

static inline u8 SdRd8(u32 base, u32 off)
{
    return (u8)(*((volatile u8 *)(uintptr_t)(base + off)));
}

static inline void SdWr8(u32 base, u32 off, u8 val)
{
    *((volatile u8 *)(uintptr_t)(base + off)) = val;
}

/* ---- Busy-wait helper (rough loop, ~1us per iteration at 666MHz) ---- */
static void udelay(u32 us)
{
    volatile u32 i;
    for (i = 0; i < us * 166U; i++) { /* ~666/4 iterations per us */ }
}

/* ---- Wait for bits in Normal Interrupt Status ---- */
static XStatus WaitForIntrBits(u32 base, u16 mask, u32 timeout_us)
{
    u32 elapsed = 0;
    u16 status;

    while (elapsed < timeout_us) {
        status = SdRd16(base, XSDPS_NORM_INTR_STS_REG);
        if (status & XSDPS_INTR_ERR_MASK) {
            u16 err = SdRd16(base, XSDPS_ERR_INTR_STS_REG);
            SdWr16(base, XSDPS_ERR_INTR_STS_REG, err);  /* clear */
            SdWr16(base, XSDPS_NORM_INTR_STS_REG, XSDPS_INTR_ERR_MASK);
            return XST_FAILURE;
        }
        if (status & mask) {
            SdWr16(base, XSDPS_NORM_INTR_STS_REG, mask);  /* W1C clear */
            return XST_SUCCESS;
        }
        udelay(10);
        elapsed += 10;
    }
    return XST_FAILURE;
}

/* ---- Send an SD command ---- */
static XStatus SendCmd(u32 base, u8 cmd_idx, u32 arg,
                       u8 resp_type,   /* 0=none 2=long 3=short 3b=busy */
                       u8 data_present)
{
    u32 timeout = XSDPS_TIMEOUT_US;
    u32 psr;

    /* Wait for CMD/DAT inhibit to clear */
    do {
        psr = SdRd32(base, XSDPS_PRES_STATE_REG);
        if (!(psr & (XSDPS_PSR_INHIBIT_CMD_MASK |
                     (data_present ? XSDPS_PSR_INHIBIT_DAT_MASK : 0U)))) {
            break;
        }
        udelay(10);
        timeout -= 10;
    } while (timeout > 0);

    if (timeout == 0) {
        return XST_FAILURE;
    }

    /* Clear any stale interrupts */
    SdWr16(base, XSDPS_NORM_INTR_STS_REG, 0xFFFFU);
    SdWr16(base, XSDPS_ERR_INTR_STS_REG,  0xFFFFU);

    /* Write argument */
    SdWr32(base, XSDPS_ARGMT_REG, arg);

    /* Build and write command register: [13:8]=cmd_idx, [1:0]=resp_type,
       [3]=CRC chk, [4]=idx chk, [5]=data present */
    u16 cmd_reg = (u16)(((u16)cmd_idx << 8) |
                        (u16)(resp_type & 0x3U) |
                        (resp_type ? (XSDPS_CMD_CRC_CHK_EN | XSDPS_CMD_INDX_CHK_EN) : 0U) |
                        (data_present ? XSDPS_CMD_DATA_PRESENT : 0U));

    /* Long response: don't check CRC/index (spec says so for CMD2, CMD9) */
    if (resp_type == 1U) { /* using 1 for long response internally */
        cmd_reg = (u16)(((u16)cmd_idx << 8) | 0x01U); /* R2 */
    }

    SdWr16(base, XSDPS_CMD_REG, cmd_reg);

    /* Wait for command complete */
    return WaitForIntrBits(base, XSDPS_INTR_CC_MASK, XSDPS_TIMEOUT_US);
}

/* ---- Reset the SD controller ---- */
static XStatus SdReset(u32 base, u8 reset_mask)
{
    u32 timeout = 100000U;
    SdWr8(base, XSDPS_SW_RST_REG, reset_mask);
    while (SdRd8(base, XSDPS_SW_RST_REG) & reset_mask) {
        udelay(10);
        if (--timeout == 0) return XST_FAILURE;
    }
    return XST_SUCCESS;
}

/* ---- Set SD clock frequency ---- */
static XStatus SetClock(u32 base, u32 input_hz, u32 target_hz)
{
    /* Stop SD clock */
    SdWr16(base, XSDPS_CLK_CTRL_REG, 0);

    /* Calculate divider (Ver 2.0 host controller 10-bit divider) */
    u32 div = 1U;
    while ((input_hz / (div * 2U)) > target_hz && div < 256U) {
        div++;
    }

    u16 clk_ctrl = (u16)(XSDPS_CC_INT_CLK_EN_MASK | ((div & 0xFFU) << 8));
    SdWr16(base, XSDPS_CLK_CTRL_REG, clk_ctrl);

    /* Wait for internal clock stable */
    u32 timeout = 50000U;
    while (!(SdRd16(base, XSDPS_CLK_CTRL_REG) & XSDPS_CC_INT_CLK_STABLE_MASK)) {
        udelay(10);
        if (--timeout == 0) return XST_FAILURE;
    }

    /* Enable SD clock */
    SdWr16(base, XSDPS_CLK_CTRL_REG, (u16)(clk_ctrl | XSDPS_CC_SD_CLK_EN_MASK));
    return XST_SUCCESS;
}

/* =====================================================================
 * Public API Implementation
 * ===================================================================== */

/* Static config table — one entry per SDIO device on the chip */
static XSdPs_Config XSdPs_ConfigTable[] = {
    {
        .DeviceId       = XPAR_XSDPS_0_DEVICE_ID,
        .BaseAddress    = XPAR_XSDPS_0_BASEADDR,
        .InputClockHz   = XPAR_XSDPS_0_SDIO_CLK_FREQ_HZ,
        .CardDetect     = XPAR_XSDPS_0_HAS_CD,
        .WriteProtect   = XPAR_XSDPS_0_HAS_WP,
        .BusWidth       = XPAR_XSDPS_0_BUS_WIDTH,
        .BankNumber     = XPAR_XSDPS_0_MIO_BANK,
        .HasEMMC        = 0,
        .IsCacheCoherent = 0,
    }
};

XSdPs_Config *XSdPs_LookupConfig(u16 DeviceId)
{
    u32 i;
    for (i = 0; i < sizeof(XSdPs_ConfigTable) / sizeof(XSdPs_Config); i++) {
        if (XSdPs_ConfigTable[i].DeviceId == DeviceId) {
            return &XSdPs_ConfigTable[i];
        }
    }
    return (XSdPs_Config *)0;
}

XStatus XSdPs_CfgInitialize(XSdPs *InstancePtr,
                              XSdPs_Config *ConfigPtr,
                              u32 EffectiveAddr)
{
    (void)EffectiveAddr;

    if (!InstancePtr || !ConfigPtr) return XST_FAILURE;

    InstancePtr->Config      = *ConfigPtr;
    InstancePtr->IsReady     = 0U;
    InstancePtr->RCA         = 0U;
    InstancePtr->CardType    = SD_LOWCAPACITY;
    InstancePtr->BlkSize     = 512U;

    u32 base = InstancePtr->Config.BaseAddress;

    /* Full software reset */
    if (SdReset(base, XSDPS_SWRST_ALL_MASK) != XST_SUCCESS) {
        xil_printf("[xsdps] Reset timeout\r\n");
        return XST_FAILURE;
    }

    /* Enable all status bits (polling mode — no interrupts to CPU) */
    SdWr16(base, XSDPS_NORM_INTR_STS_EN_REG, 0xFFFFU);
    SdWr16(base, XSDPS_ERR_INTR_STS_EN_REG,  0xFFFFU);
    /* Disable signal (CPU IRQ) generation */
    SdWr16(base, XSDPS_NORM_INTR_SIG_EN_REG, 0x0000U);
    SdWr16(base, XSDPS_ERR_INTR_SIG_EN_REG,  0x0000U);

    /* Power on, 3.3V */
    SdWr8(base, XSDPS_POWER_CTRL_REG, (u8)(XSDPS_PC_BUS_VSEL_3V3_MASK | XSDPS_PC_BUS_PWR_MASK));
    udelay(1000);

    /* Timeout control: SDCLK * 2^(value+13), set to 0xE = max */
    SdWr8(base, XSDPS_TIMEOUT_CTRL_REG, 0x0EU);

    /* Start at low clock: 400 kHz (identification mode) */
    if (SetClock(base, InstancePtr->Config.InputClockHz, 400000U) != XST_SUCCESS) {
        xil_printf("[xsdps] Clock set 400kHz failed\r\n");
        return XST_FAILURE;
    }

    /* Set block size to 512 */
    SdWr16(base, XSDPS_BLK_SIZE_REG, 512U);

    InstancePtr->IsReady = 1U;
    return XST_SUCCESS;
}

XStatus XSdPs_CardInitialize(XSdPs *InstancePtr)
{
    if (!InstancePtr || !InstancePtr->IsReady) return XST_FAILURE;

    u32 base = InstancePtr->Config.BaseAddress;
    u32 resp;
    u32 timeout;
    XStatus status;

    /* CMD0 — GO_IDLE_STATE */
    (void)SendCmd(base, CMD0, 0, 0, 0);
    udelay(2000);

    /* CMD8 — SEND_IF_COND: check 2.7-3.6V support */
    status = SendCmd(base, CMD8, CMD8_VOL_PATTERN, 2, 0); /* R7 = short */
    if (status != XST_SUCCESS) {
        xil_printf("[xsdps] CMD8 no response — SD v1 card?\r\n");
    }

    /* ACMD41 loop — wait for card ready, set HCS bit for SDHC support */
    timeout = 100;
    do {
        /* CMD55 — APP_CMD (before ACMD) */
        (void)SendCmd(base, CMD55, 0, 2, 0); /* R1 = short */

        /* ACMD41 — SD_SEND_OP_COND with HCS | voltage range */
        status = SendCmd(base, ACMD41,
                         (u32)(ACMD41_HCS_MASK | ACMD41_OCR_33V), 2, 0); /* R3 */
        if (status != XST_SUCCESS) {
            xil_printf("[xsdps] ACMD41 failed\r\n");
            return XST_FAILURE;
        }
        resp = SdRd32(base, XSDPS_RESP0_REG);
        udelay(10000);  /* 10 ms between polls */
    } while (!(resp & ACMD41_BUSY_MASK) && --timeout > 0);

    if (timeout == 0) {
        xil_printf("[xsdps] Card power-up timed out\r\n");
        return XST_FAILURE;
    }

    /* Check CCS (Card Capacity Status) bit in OCR */
    InstancePtr->CardType = (resp & ACMD41_HCS_MASK) ? SD_HIGHCAPACITY : SD_LOWCAPACITY;
    xil_printf("[xsdps] Card type: %s\r\n",
               InstancePtr->CardType ? "SDHC/SDXC" : "SD Standard");

    /* CMD2 — ALL_SEND_CID */
    (void)SendCmd(base, CMD2, 0, 1, 0); /* R2 long */

    /* CMD3 — SEND_RELATIVE_ADDR */
    status = SendCmd(base, CMD3, 0, 2, 0); /* R6 short */
    if (status != XST_SUCCESS) {
        xil_printf("[xsdps] CMD3 failed\r\n");
        return XST_FAILURE;
    }
    InstancePtr->RCA = SdRd32(base, XSDPS_RESP0_REG) >> 16;
    xil_printf("[xsdps] RCA = 0x%04X\r\n", InstancePtr->RCA);

    /* CMD7 — SELECT_CARD (put into transfer state) */
    status = SendCmd(base, CMD7, InstancePtr->RCA << 16, 3, 0); /* R1b */
    if (status != XST_SUCCESS) {
        xil_printf("[xsdps] CMD7 SELECT failed\r\n");
        return XST_FAILURE;
    }

    /* CMD55 + ACMD6 — SET_BUS_WIDTH to 4-bit */
    (void)SendCmd(base, CMD55, InstancePtr->RCA << 16, 2, 0);
    status = SendCmd(base, ACMD6, 2U, 2, 0); /* arg=2 means 4-bit bus */
    if (status != XST_SUCCESS) {
        xil_printf("[xsdps] ACMD6 bus width failed (ok on 1-bit cards)\r\n");
    } else {
        /* Set 4-bit mode in host controller */
        u8 hc1 = SdRd8(base, XSDPS_HOST_CTRL1_REG);
        SdWr8(base, XSDPS_HOST_CTRL1_REG, (u8)(hc1 | (1U << 1))); /* DAT width=4 */
    }

    /* CMD16 — SET_BLOCKLEN (only needed for standard capacity) */
    if (InstancePtr->CardType == SD_LOWCAPACITY) {
        status = SendCmd(base, CMD16, 512U, 2, 0);
        if (status != XST_SUCCESS) {
            xil_printf("[xsdps] CMD16 failed\r\n");
            return XST_FAILURE;
        }
    }

    /* Switch to high-speed clock: 25 MHz */
    if (SetClock(base, InstancePtr->Config.InputClockHz, 25000000U) != XST_SUCCESS) {
        xil_printf("[xsdps] Failed to switch to 25MHz\r\n");
    }

    InstancePtr->BlkSize = 512U;
    xil_printf("[xsdps] Card initialized successfully.\r\n");
    return XST_SUCCESS;
}

XStatus XSdPs_ReadPolled(XSdPs *InstancePtr,
                          u32 StartLBA,
                          u32 NumBlocks,
                          u8 *Buff)
{
    if (!InstancePtr || !InstancePtr->IsReady || !Buff) return XST_FAILURE;

    u32 base = InstancePtr->Config.BaseAddress;
    u32 addr = (InstancePtr->CardType == SD_HIGHCAPACITY) ?
               StartLBA : StartLBA * 512U;

    /* Set block count */
    SdWr16(base, XSDPS_BLK_CNT_REG, (u16)NumBlocks);

    /* Transfer mode: multi-block, block count enable, read direction */
    u16 xfer_mode = (u16)(XSDPS_TM_BLK_CNT_EN_MASK |
                          XSDPS_TM_DAT_DIR_SEL_MASK |   /* card→host */
                          (NumBlocks > 1U ? (XSDPS_TM_MUL_SIN_BLK_SEL_MASK |
                                             XSDPS_TM_AUTO_CMD12_MASK) : 0U));
    SdWr16(base, XSDPS_XFER_MODE_REG, xfer_mode);

    /* Issue CMD17 (single) or CMD18 (multiple) */
    u8 cmd = (NumBlocks == 1U) ? CMD17 : CMD18;
    if (SendCmd(base, cmd, addr, 2, 1) != XST_SUCCESS) {
        xil_printf("[xsdps] ReadPolled CMD%d failed\r\n", cmd);
        return XST_FAILURE;
    }

    /* Read data block(s) from FIFO */
    u32 total_words = NumBlocks * (512U / 4U);
    u32 *word_buf = (u32 *)Buff;

    for (u32 block = 0; block < NumBlocks; block++) {
        /* Wait for buffer-read-ready */
        if (WaitForIntrBits(base, XSDPS_INTR_BRR_MASK, XSDPS_TIMEOUT_US) != XST_SUCCESS) {
            xil_printf("[xsdps] Buffer read ready timeout (block %d)\r\n", block);
            return XST_FAILURE;
        }
        u32 words_per_block = 512U / 4U;
        for (u32 w = 0; w < words_per_block; w++) {
            word_buf[(block * words_per_block) + w] = SdRd32(base, XSDPS_BUF_ACCESS_REG);
        }
    }

    /* Wait for transfer complete */
    if (WaitForIntrBits(base, XSDPS_INTR_TC_MASK, XSDPS_TIMEOUT_US) != XST_SUCCESS) {
        xil_printf("[xsdps] Transfer complete timeout\r\n");
        return XST_FAILURE;
    }

    (void)total_words;
    return XST_SUCCESS;
}

XStatus XSdPs_WritePolled(XSdPs *InstancePtr,
                           u32 StartLBA,
                           u32 NumBlocks,
                           const u8 *Buff)
{
    if (!InstancePtr || !InstancePtr->IsReady || !Buff) return XST_FAILURE;

    u32 base = InstancePtr->Config.BaseAddress;
    u32 addr = (InstancePtr->CardType == SD_HIGHCAPACITY) ?
               StartLBA : StartLBA * 512U;

    /* Set block count */
    SdWr16(base, XSDPS_BLK_CNT_REG, (u16)NumBlocks);

    /* Transfer mode: multi-block, block count enable, write direction */
    u16 xfer_mode = (u16)(XSDPS_TM_BLK_CNT_EN_MASK |
                          (NumBlocks > 1U ? (XSDPS_TM_MUL_SIN_BLK_SEL_MASK |
                                             XSDPS_TM_AUTO_CMD12_MASK) : 0U));
    /* DAT_DIR_SEL = 0 for host→card (write) */
    SdWr16(base, XSDPS_XFER_MODE_REG, xfer_mode);

    /* Issue CMD24 (single) or CMD25 (multiple) */
    u8 cmd = (NumBlocks == 1U) ? CMD24 : CMD25;
    if (SendCmd(base, cmd, addr, 2, 1) != XST_SUCCESS) {
        xil_printf("[xsdps] WritePolled CMD%d failed\r\n", cmd);
        return XST_FAILURE;
    }

    /* Write data block(s) to FIFO */
    const u32 *word_buf = (const u32 *)Buff;

    for (u32 block = 0; block < NumBlocks; block++) {
        /* Wait for buffer-write-ready */
        if (WaitForIntrBits(base, XSDPS_INTR_BWR_MASK, XSDPS_TIMEOUT_US) != XST_SUCCESS) {
            xil_printf("[xsdps] Buffer write ready timeout (block %d)\r\n", block);
            return XST_FAILURE;
        }
        u32 words_per_block = 512U / 4U;
        for (u32 w = 0; w < words_per_block; w++) {
            SdWr32(base, XSDPS_BUF_ACCESS_REG, word_buf[(block * words_per_block) + w]);
        }
    }

    /* Wait for transfer complete */
    if (WaitForIntrBits(base, XSDPS_INTR_TC_MASK, XSDPS_TIMEOUT_US) != XST_SUCCESS) {
        xil_printf("[xsdps] Write transfer complete timeout\r\n");
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}

