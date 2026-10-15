// ============================================================================
// Module: rv32i_sd_pure_top
// Description: 100% Pure Verilog System for Digilent Zybo Z7-10.
//              - ZERO Xilinx proprietary IP blocks (No Zynq PS / No ARM / No Vitis)
//              - Directly synthesizable with F4PGA (Yosys + prjxray) or Vivado
//              - Direct SPI SD Card Reader hardware (connected to Zybo Pmod JE)
//              - Integrated with user custom RV32I processor core
// ============================================================================

`timescale 1ns / 1ps

module rv32i_sd_pure_top #(
    parameter CLK_FREQ_HZ = 125_000_000
)(
    // Zybo Z7-10 125 MHz System Clock & Reset Button
    input  wire        sys_clk,    // Pin K17 (125 MHz Ethernet clock)
    input  wire        btn0,       // Pin K18 (BTN0: Reset, active high)

    // MicroSD SPI Interface (Zybo Z7-10 Pmod JE)
    output wire        sd_cs_n,    // Pin V12 (Pmod JE Pin 1)
    output wire        sd_mosi,    // Pin W16 (Pmod JE Pin 2)
    input  wire        sd_miso,    // Pin J15 (Pmod JE Pin 3)
    output wire        sd_sclk,    // Pin H15 (Pmod JE Pin 4)
    input  wire        sd_cd,      // Pin V13 (Pmod JE Pin 9, Card Detect)

    // Zybo Z7-10 Onboard Diagnostic LEDs
    output wire [3:0]  led
);

    wire reset = btn0;
    wire rst_n = ~reset;

    // =========================================================================
    // RV32I CPU Memory Bus Wires
    // =========================================================================
    wire [31:0] pc_debug;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire        mem_write;
    wire        mem_read;
    wire [31:0] ext_mem_rdata;

    // =========================================================================
    // 1. User Custom RV32I Core Datapath
    // =========================================================================
    Datapath cpu (
        .clk           (sys_clk),
        .reset         (reset),
        .pcRegister    (pc_debug),
        .mem_addr      (mem_addr),
        .mem_wdata     (mem_wdata),
        .mem_write     (mem_write),
        .mem_read      (mem_read),
        .ext_mem_rdata (ext_mem_rdata)
    );

    // =========================================================================
    // 2. Pure Verilog SD Card Hardware Controller (SPI Mode)
    // =========================================================================
    wire sd_busy;
    wire sd_done;

    sd_spi_controller #(
        .CLK_FREQ_HZ   (CLK_FREQ_HZ),
        .ADDR_WIDTH    (12),
        .DATA_WIDTH    (32)
    ) sd_controller (
        .clk           (sys_clk),
        .rst_n         (rst_n),

        // Physical SPI Pins (to Pmod JE)
        .sd_sclk       (sd_sclk),
        .sd_cs_n       (sd_cs_n),
        .sd_mosi       (sd_mosi),
        .sd_miso       (sd_miso),
        .sd_cd         (sd_cd),

        // Direct CPU Memory-Mapped Bus (Base: 0x43C0_0000)
        .cpu_addr      (mem_addr[11:0]),
        .cpu_wdata     (mem_wdata),
        .cpu_write     (mem_write),
        .cpu_read      (mem_read),
        .cpu_rdata     (ext_mem_rdata),

        .irq_done      (sd_done)
    );

    // =========================================================================
    // 3. Status Signals & Physical LEDs on Zybo Z7
    // =========================================================================
    // Check if RV32 register x5 contains 0x55AA (MBR signature from Sector 0)
    wire [31:0] reg_x5 = cpu.registerFile.x5;
    wire mbr_valid = (reg_x5[31:16] == 16'hAA55) || (reg_x5[15:0] == 16'h55AA);

    assign led[0] = rst_n;                 // LD0: System Active / Reset released
    assign led[1] = (sd_controller.reg_status == 32'd1); // LD1: SD Controller BUSY
    assign led[2] = sd_done;               // LD2: Sector Read DONE
    assign led[3] = mbr_valid;             // LD3: MBR Signature (0x55AA) Verified by RV32!

endmodule

