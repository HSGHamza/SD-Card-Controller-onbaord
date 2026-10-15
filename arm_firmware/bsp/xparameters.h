/*
 * xparameters.h — Minimal hardware address map for Zybo Z7-10
 *
 * This file replaces the Vitis-generated xparameters.h.
 * All addresses are taken directly from the Zynq-7000 TRM and the
 * Zybo Z7-10 reference design (PS SDIO0 on MIO 40-45).
 *
 * The mailbox base is 0x43C00000 — matches the AXI Slave GP0 address
 * assigned in build_zybo_project.tcl.
 */

#ifndef XPARAMETERS_H
#define XPARAMETERS_H

/* ===== Processor ===== */
#define XPAR_CPU_CORTEXA9_CORE_CLOCK_FREQ_HZ   666666687U
#define XPAR_CPU_CORTEXA9_0_CPU_CLK_FREQ_HZ    666666687U

/* ===== UART 1 (MIO 48-49) ===== */
#define XPAR_PS7_UART_1_DEVICE_ID               1
#define XPAR_PS7_UART_1_BASEADDR                0xE0001000U
#define XPAR_PS7_UART_1_HIGHADDR                0xE0001FFFU
#define XPAR_PS7_UART_1_UART_CLK_FREQ_HZ       100000000U
#define XPAR_PS7_UART_1_HAS_MODEM               0

/* ===== SD / SDIO 0 (MIO 40-45) ===== */
#define XPAR_XSDPS_0_DEVICE_ID                  0
#define XPAR_XSDPS_0_BASEADDR                   0xE0100000U
#define XPAR_XSDPS_0_HIGHADDR                   0xE0100FFFU
#define XPAR_XSDPS_0_SDIO_CLK_FREQ_HZ          100000000U
#define XPAR_XSDPS_0_HAS_CD                     1
#define XPAR_XSDPS_0_HAS_WP                     0
#define XPAR_XSDPS_0_BUS_WIDTH                  4
#define XPAR_XSDPS_0_MIO_BANK                   1
#define XPAR_XSDPS_0_CARD_DETECT_POLARITY       0

/* ===== AXI SD Mailbox in PL (GP0 Slave) ===== */
#define XPAR_AXI_SD_MAILBOX_0_S_AXI_BASEADDR   0x43C00000U
#define XPAR_AXI_SD_MAILBOX_0_S_AXI_HIGHADDR   0x43C0FFFFU

/* ===== DDR SDRAM ===== */
#define XPAR_PS7_DDR_0_S_AXI_BASEADDR          0x00100000U
#define XPAR_PS7_DDR_0_S_AXI_HIGHADDR          0x1FFFFFFFU

/* ===== OCM (On-Chip Memory) ===== */
#define XPAR_PS7_RAM_0_S_AXI_BASEADDR          0x00000000U
#define XPAR_PS7_RAM_0_S_AXI_HIGHADDR          0x0002FFFFU

#endif /* XPARAMETERS_H */

