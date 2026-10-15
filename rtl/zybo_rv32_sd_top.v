// ============================================================================
// Module: zybo_rv32_sd_top
// Description: Complete Top-Level Verilog Module for Digilent Zybo Z7-10.
//              Directly synthesizable into a bitstream in Vivado.
//              Integrates:
//                1. Zynq Processing System (system.bd wrapper: ARM, DDR, SDIO, UART)
//                2. User RV32I Core + SD Mailbox (rv32i_sd_system)
//                3. Diagnostic LEDs (M14, M15, G14, D18)
// ============================================================================

`timescale 1ns / 1ps

module zybo_rv32_sd_top (
    // Zynq PS Fixed DDR Pins
    inout  wire [14:0] DDR_addr,
    inout  wire [2:0]  DDR_ba,
    inout  wire        DDR_cas_n,
    inout  wire        DDR_cke_out,
    inout  wire        DDR_clk_n,
    inout  wire        DDR_clk_p,
    inout  wire        DDR_cs_n,
    inout  wire [3:0]  DDR_dm,
    inout  wire [31:0] DDR_dq,
    inout  wire [3:0]  DDR_dqs_n,
    inout  wire [3:0]  DDR_dqs_p,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,

    // Zynq PS Fixed MIO Pins (MIO 40-45 SDIO, 47 CD, 48-49 UART)
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb,

    // PL User IO (Zybo Z7-10 Board LEDs)
    output wire [3:0]  led,
    input  wire [3:0]  btn,
    input  wire [3:0]  sw
);

    // Clocks and Reset from Zynq PS
    wire fclk_clk0;     // 100 MHz clock from PS
    wire fclk_reset0_n; // Active-low reset from PS
    wire sys_rst = ~fclk_reset0_n;

    // AXI Bus: ARM PS (Master GP0) -> RV32 SD System (Slave)
    wire [31:0] arm_axi_awaddr;
    wire [2:0]  arm_axi_awprot;
    wire        arm_axi_awvalid;
    wire        arm_axi_awready;

    wire [31:0] arm_axi_wdata;
    wire [3:0]  arm_axi_wstrb;
    wire        arm_axi_wvalid;
    wire        arm_axi_wready;

    wire [1:0]  arm_axi_bresp;
    wire        arm_axi_bvalid;
    wire        arm_axi_bready;

    wire [31:0] arm_axi_araddr;
    wire [2:0]  arm_axi_arprot;
    wire        arm_axi_arvalid;
    wire        arm_axi_arready;

    wire [31:0] arm_axi_rdata;
    wire [1:0]  arm_axi_rresp;
    wire        arm_axi_rvalid;
    wire        arm_axi_rready;

    // Diagnostic Signals
    wire        irq_arm;
    wire        irq_rv32;
    wire [31:0] pc_debug;

    // =========================================================================
    // 1. Zynq Processing System Subsystem (Vivado Block Design instance)
    // =========================================================================
    system ps_subsystem (
        .DDR_addr          (DDR_addr),
        .DDR_ba            (DDR_ba),
        .DDR_cas_n         (DDR_cas_n),
        .DDR_cke_out       (DDR_cke_out),
        .DDR_clk_n         (DDR_clk_n),
        .DDR_clk_p         (DDR_clk_p),
        .DDR_cs_n          (DDR_cs_n),
        .DDR_dm            (DDR_dm),
        .DDR_dq            (DDR_dq),
        .DDR_dqs_n         (DDR_dqs_n),
        .DDR_dqs_p         (DDR_dqs_p),
        .DDR_odt           (DDR_odt),
        .DDR_ras_n         (DDR_ras_n),
        .DDR_reset_n       (DDR_reset_n),
        .DDR_we_n          (DDR_we_n),

        .FIXED_IO_ddr_vrn  (FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp  (FIXED_IO_ddr_vrp),
        .FIXED_IO_mio      (FIXED_IO_mio),
        .FIXED_IO_ps_clk   (FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb  (FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb (FIXED_IO_ps_srstb),

        .FCLK_CLK0         (fclk_clk0),
        .FCLK_RESET0_N     (fclk_reset0_n),

        // M_AXI_GP0
        .M_AXI_GP0_awaddr  (arm_axi_awaddr),
        .M_AXI_GP0_awprot  (arm_axi_awprot),
        .M_AXI_GP0_awvalid (arm_axi_awvalid),
        .M_AXI_GP0_awready (arm_axi_awready),
        .M_AXI_GP0_wdata   (arm_axi_wdata),
        .M_AXI_GP0_wstrb   (arm_axi_wstrb),
        .M_AXI_GP0_wvalid  (arm_axi_wvalid),
        .M_AXI_GP0_wready  (arm_axi_wready),
        .M_AXI_GP0_bresp   (arm_axi_bresp),
        .M_AXI_GP0_bvalid  (arm_axi_bvalid),
        .M_AXI_GP0_bready  (arm_axi_bready),
        .M_AXI_GP0_araddr  (arm_axi_araddr),
        .M_AXI_GP0_arprot  (arm_axi_arprot),
        .M_AXI_GP0_arvalid (arm_axi_arvalid),
        .M_AXI_GP0_arready (arm_axi_arready),
        .M_AXI_GP0_rdata   (arm_axi_rdata),
        .M_AXI_GP0_rresp   (arm_axi_rresp),
        .M_AXI_GP0_rvalid  (arm_axi_rvalid),
        .M_AXI_GP0_rready  (arm_axi_rready),

        .IRQ_F2P           (irq_arm)
    );

    // =========================================================================
    // 2. Integrated RV32I Core + SD Mailbox
    // =========================================================================
    rv32i_sd_system #(
        .AXI_ADDR_WIDTH    (12),
        .AXI_DATA_WIDTH    (32)
    ) rv32i_system_inst (
        .clk               (fclk_clk0),
        .reset             (sys_rst),

        // Port A: ARM Cortex-A9 Interface
        .s_arm_awaddr      (arm_axi_awaddr[11:0]),
        .s_arm_awprot      (arm_axi_awprot),
        .s_arm_awvalid     (arm_axi_awvalid),
        .s_arm_awready     (arm_axi_awready),
        .s_arm_wdata       (arm_axi_wdata),
        .s_arm_wstrb       (arm_axi_wstrb),
        .s_arm_wvalid      (arm_axi_wvalid),
        .s_arm_wready      (arm_axi_wready),
        .s_arm_bresp       (arm_axi_bresp),
        .s_arm_bvalid      (arm_axi_bvalid),
        .s_arm_bready      (arm_axi_bready),
        .s_arm_araddr      (arm_axi_araddr[11:0]),
        .s_arm_arprot      (arm_axi_arprot),
        .s_arm_arvalid     (arm_axi_arvalid),
        .s_arm_arready     (arm_axi_arready),
        .s_arm_rdata       (arm_axi_rdata),
        .s_arm_rresp       (arm_axi_rresp),
        .s_arm_rvalid      (arm_axi_rvalid),
        .s_arm_rready      (arm_axi_rready),

        // Diagnostic outputs
        .irq_arm           (irq_arm),
        .irq_rv32          (irq_rv32),
        .pc_debug          (pc_debug)
    );

    // Check if RV32 loaded valid MBR signature (0x55AA)
    wire [31:0] reg_x5 = rv32i_system_inst.cpu.registerFile.x5;
    wire mbr_valid     = (reg_x5[31:16] == 16'hAA55) || (reg_x5[15:0] == 16'h55AA);

    // =========================================================================
    // 3. Real-Time Physical LED Indicators on Zybo Z7-10
    // =========================================================================
    assign led[0] = fclk_reset0_n;  // LD0: System Ready / Clock Running
    assign led[1] = irq_arm;        // LD1: RV32 Request Active
    assign led[2] = irq_rv32;       // LD2: SD Sector Transfer Complete
    assign led[3] = mbr_valid;      // LD3: Valid MBR (0x55AA) Verified by RV32!

endmodule
