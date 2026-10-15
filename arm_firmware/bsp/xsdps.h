/*
 * xsdps.h — Minimal Zynq-7000 PS SDIO driver header
 *
 * Derived from Xilinx embeddedsw (Apache-2.0 / MIT).
 * Source: https://github.com/Xilinx/embeddedsw/tree/master/XilinxProcessorIPLib/drivers/sdps
 *
 * This is a self-contained header for use with arm-none-eabi-gcc without Vitis.
 * It provides only what sd_mailbox_server.c needs:
 *   - XSdPs_Config, XSdPs structs
 *   - XSdPs_LookupConfig, XSdPs_CfgInitialize, XSdPs_CardInitialize
 *   - XSdPs_ReadPolled, XSdPs_WritePolled
 *
 * All implementation is in xsdps.c (also hand-written, no BSP needed).
 */

#ifndef XSDPS_H
#define XSDPS_H

#include "xil_types.h"
#include "xparameters.h"

/* ---- SDIO Register Offsets (Zynq-7000 TRM Table 18-10) ---- */
#define XSDPS_BLK_SIZE_REG          0x0004U  /* Block size */
#define XSDPS_BLK_CNT_REG           0x0006U  /* Block count */
#define XSDPS_ARGMT_REG             0x0008U  /* Argument */
#define XSDPS_XFER_MODE_REG         0x000CU  /* Transfer mode */
#define XSDPS_CMD_REG               0x000EU  /* Command */
#define XSDPS_RESP0_REG             0x0010U  /* Response 0 */
#define XSDPS_RESP1_REG             0x0014U  /* Response 1 */
#define XSDPS_RESP2_REG             0x0018U  /* Response 2 */
#define XSDPS_RESP3_REG             0x001CU  /* Response 3 */
#define XSDPS_BUF_ACCESS_REG        0x0020U  /* Buffer data port */
#define XSDPS_PRES_STATE_REG        0x0024U  /* Present state */
#define XSDPS_HOST_CTRL1_REG        0x0028U  /* Host control 1 */
#define XSDPS_POWER_CTRL_REG        0x0029U  /* Power control */
#define XSDPS_CLK_CTRL_REG          0x002CU  /* Clock control */
#define XSDPS_TIMEOUT_CTRL_REG      0x002EU  /* Timeout control */
#define XSDPS_SW_RST_REG            0x002FU  /* Software reset */
#define XSDPS_NORM_INTR_STS_REG     0x0030U  /* Normal interrupt status */
#define XSDPS_ERR_INTR_STS_REG      0x0032U  /* Error interrupt status */
#define XSDPS_NORM_INTR_STS_EN_REG  0x0034U  /* Normal intr status enable */
#define XSDPS_ERR_INTR_STS_EN_REG   0x0036U  /* Error intr status enable */
#define XSDPS_NORM_INTR_SIG_EN_REG  0x0038U  /* Normal intr signal enable */
#define XSDPS_ERR_INTR_SIG_EN_REG   0x003AU  /* Error intr signal enable */
#define XSDPS_HOST_CTRL2_REG        0x003EU  /* Host control 2 */
#define XSDPS_CAPS_REG              0x0040U  /* Capabilities */
#define XSDPS_CLK_DIV_MAX           0x3FFU   /* Max clock divider */

/* ---- Present State bits ---- */
#define XSDPS_PSR_INHIBIT_CMD_MASK  (1U << 0)
#define XSDPS_PSR_INHIBIT_DAT_MASK  (1U << 1)
#define XSDPS_PSR_BUF_RD_EN_MASK    (1U << 11)
#define XSDPS_PSR_BUF_WR_EN_MASK    (1U << 10)
#define XSDPS_PSR_CARD_DPL_MASK     (1U << 18)
#define XSDPS_PSR_CARD_STABLE_MASK  (1U << 17)
#define XSDPS_PSR_CARD_INSRT_MASK   (1U << 16)

/* ---- Normal Interrupt Status bits ---- */
#define XSDPS_INTR_CC_MASK          (1U << 0)   /* Command complete */
#define XSDPS_INTR_TC_MASK          (1U << 1)   /* Transfer complete */
#define XSDPS_INTR_BWR_MASK         (1U << 4)   /* Buffer write ready */
#define XSDPS_INTR_BRR_MASK         (1U << 5)   /* Buffer read ready */
#define XSDPS_INTR_CARD_MASK        (1U << 8)   /* Card interrupt */
#define XSDPS_INTR_ERR_MASK         (1U << 15)  /* Error interrupt */

/* ---- Error Interrupt Status bits ---- */
#define XSDPS_INTR_ERR_CT_MASK      (1U << 0)   /* Command timeout */
#define XSDPS_INTR_ERR_CCRC_MASK    (1U << 1)   /* Command CRC */
#define XSDPS_INTR_ERR_CEB_MASK     (1U << 2)   /* Command end bit */
#define XSDPS_INTR_ERR_CI_MASK      (1U << 3)   /* Command index */
#define XSDPS_INTR_ERR_DT_MASK      (1U << 4)   /* Data timeout */
#define XSDPS_INTR_ERR_DCRC_MASK    (1U << 5)   /* Data CRC */
#define XSDPS_INTR_ERR_DEB_MASK     (1U << 6)   /* Data end bit */

/* ---- Command register encodings ---- */
#define XSDPS_CMD_NO_RESP           0x00U
#define XSDPS_CMD_RESP_LONG         (3U << 0)
#define XSDPS_CMD_RESP_SHORT        (2U << 0)
#define XSDPS_CMD_RESP_SHORT_BUSY   (3U << 0)
#define XSDPS_CMD_CRC_CHK_EN        (1U << 3)
#define XSDPS_CMD_INDX_CHK_EN       (1U << 4)
#define XSDPS_CMD_DATA_PRESENT      (1U << 5)

/* ---- Transfer mode bits ---- */
#define XSDPS_TM_DMA_EN_MASK        (1U << 0)
#define XSDPS_TM_BLK_CNT_EN_MASK   (1U << 1)
#define XSDPS_TM_AUTO_CMD12_MASK    (1U << 2)
#define XSDPS_TM_DAT_DIR_SEL_MASK   (1U << 4)   /* 1=read (card→host) */
#define XSDPS_TM_MUL_SIN_BLK_SEL_MASK (1U << 5)/* 1=multi block */

/* ---- Host Control 1 bits ---- */
#define XSDPS_HC_DMA_MASK           (3U << 3)   /* DMA select */
#define XSDPS_HC_DMA_ADMA2_32_MASK  (2U << 3)

/* ---- Software Reset bits ---- */
#define XSDPS_SWRST_ALL_MASK        (1U << 0)
#define XSDPS_SWRST_CMD_MASK        (1U << 1)
#define XSDPS_SWRST_DAT_MASK        (1U << 2)

/* ---- Clock Control bits ---- */
#define XSDPS_CC_INT_CLK_EN_MASK    (1U << 0)
#define XSDPS_CC_INT_CLK_STABLE_MASK (1U << 1)
#define XSDPS_CC_SD_CLK_EN_MASK     (1U << 2)
#define XSDPS_CC_SDCLK_FREQ_SEL_EXT_MASK (0x3U << 6)
#define XSDPS_CC_SDCLK_FREQ_SEL_MASK (0xFFU << 8)

/* ---- Power Control ---- */
#define XSDPS_PC_BUS_PWR_MASK       (1U << 0)
#define XSDPS_PC_BUS_VSEL_MASK      (7U << 1)
#define XSDPS_PC_BUS_VSEL_3V3_MASK  (7U << 1)

/* ---- SD/MMC Commands ---- */
#define CMD0    0U   /* GO_IDLE_STATE         */
#define CMD2    2U   /* ALL_SEND_CID          */
#define CMD3    3U   /* SEND_RELATIVE_ADDR    */
#define CMD7    7U   /* SELECT_CARD           */
#define CMD8    8U   /* SEND_IF_COND          */
#define CMD9    9U   /* SEND_CSD              */
#define CMD16   16U  /* SET_BLOCKLEN          */
#define CMD17   17U  /* READ_SINGLE_BLOCK     */
#define CMD18   18U  /* READ_MULTIPLE_BLOCK   */
#define CMD24   24U  /* WRITE_BLOCK           */
#define CMD25   25U  /* WRITE_MULTIPLE_BLOCK  */
#define CMD55   55U  /* APP_CMD               */
#define ACMD41  41U  /* SD_SEND_OP_COND (after CMD55) */
#define ACMD6   6U   /* SET_BUS_WIDTH         */

#define CMD8_VOL_PATTERN    0x1AAU
#define ACMD41_HCS_MASK     (1U << 30)  /* Host Capacity Support */
#define ACMD41_BUSY_MASK    (1U << 31)  /* Card power-up status bit */
#define ACMD41_OCR_33V      0x00FF8000U /* 3.2V-3.6V voltage range */
#define SD_HIGHCAPACITY     (1U)
#define SD_LOWCAPACITY      (0U)

/* ---- Timeouts ---- */
#define XSDPS_TIMEOUT_US            1000000U  /* 1 second in microseconds */

/* ---- Configuration structure (one per device) ---- */
typedef struct {
    u16  DeviceId;          /* Device ID */
    u32  BaseAddress;       /* SDIO controller base address */
    u32  InputClockHz;      /* Reference input clock (from PS clock) */
    u32  CardDetect;        /* 1=CD pin present */
    u32  WriteProtect;      /* 1=WP pin present */
    u32  BusWidth;          /* 1 or 4 bit bus */
    u32  BankNumber;        /* MIO bank number */
    u32  HasEMMC;           /* 1=eMMC, 0=SD */
    u32  IsCacheCoherent;   /* 1=cache coherent */
    u32  CLKPHASEUHSMode;   /* UHS clock phase */
    u32  CLKPHASESDRMode;   /* SDR clock phase */
    u32  CLKPHASEDDRMode;   /* DDR clock phase */
} XSdPs_Config;

/* ---- Driver instance structure ---- */
typedef struct {
    XSdPs_Config    Config;     /* Hardware configuration */
    u32             IsReady;    /* Device is initialized and ready */
    u32             HC_Version; /* Host controller version */
    u32             RCA;        /* Relative Card Address */
    u8              CardType;   /* SD_HIGHCAPACITY or SD_LOWCAPACITY */
    u32             BlkSize;    /* Current block size */
} XSdPs;

/* ---- Public API ---- */

/**
 * Look up hardware configuration for a device.
 * @param DeviceId  Device ID from xparameters.h
 * @return Pointer to configuration, or NULL if not found.
 */
XSdPs_Config *XSdPs_LookupConfig(u16 DeviceId);

/**
 * Initialize the driver instance.
 * @param InstancePtr  Pointer to driver instance.
 * @param ConfigPtr    Pointer to configuration (from LookupConfig).
 * @param EffectiveAddr  Effective base address (usually ConfigPtr->BaseAddress).
 * @return XST_SUCCESS or XST_FAILURE.
 */
XStatus XSdPs_CfgInitialize(XSdPs *InstancePtr,
                              XSdPs_Config *ConfigPtr,
                              u32 EffectiveAddr);

/**
 * Initialize the SD card (power-up sequence, card identification).
 * @param InstancePtr  Pointer to initialized driver instance.
 * @return XST_SUCCESS or XST_FAILURE.
 */
XStatus XSdPs_CardInitialize(XSdPs *InstancePtr);

/**
 * Read one or more 512-byte sectors using CPU-polled I/O.
 * @param InstancePtr   Pointer to initialized driver instance.
 * @param StartLBA      Starting logical block address.
 * @param NumBlocks     Number of 512-byte blocks to read.
 * @param Buff          Destination buffer (must be 4-byte aligned).
 * @return XST_SUCCESS or XST_FAILURE.
 */
XStatus XSdPs_ReadPolled(XSdPs *InstancePtr,
                          u32 StartLBA,
                          u32 NumBlocks,
                          u8 *Buff);

/**
 * Write one or more 512-byte sectors using CPU-polled I/O.
 * @param InstancePtr   Pointer to initialized driver instance.
 * @param StartLBA      Starting logical block address.
 * @param NumBlocks     Number of 512-byte blocks to write.
 * @param Buff          Source buffer (must be 4-byte aligned).
 * @return XST_SUCCESS or XST_FAILURE.
 */
XStatus XSdPs_WritePolled(XSdPs *InstancePtr,
                           u32 StartLBA,
                           u32 NumBlocks,
                           const u8 *Buff);

#endif /* XSDPS_H */

