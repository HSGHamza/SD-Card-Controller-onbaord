// ============================================================================
// Module: rv32i_sd_system
// Description: Integrated RV32I Core with Onboard SD Mailbox Controller.
//              - Integrates the user's custom RV32I Datapath
//              - Memory-maps local RAM (< 0x4000_0000) and SD Mailbox (0x43C0_0000)
//              - Connects to ARM Cortex-A9 via standard AXI4-Lite (M_AXI_GP0)
// ============================================================================

`timescale 1ns / 1ps

module rv32i_sd_system #(
    parameter AXI_ADDR_WIDTH = 12,
    parameter AXI_DATA_WIDTH = 32
)(
    input  wire                      clk,
    input  wire                      reset,

    // =========================================================================
    // ARM Cortex-A9 Interface (Connected to PS M_AXI_GP0)
    // =========================================================================
    input  wire [AXI_ADDR_WIDTH-1:0] s_arm_awaddr,
    input  wire [2:0]                s_arm_awprot,
    input  wire                      s_arm_awvalid,
    output wire                      s_arm_awready,

    input  wire [AXI_DATA_WIDTH-1:0] s_arm_wdata,
    input  wire [3:0]                s_arm_wstrb,
    input  wire                      s_arm_wvalid,
    output wire                      s_arm_wready,

    output wire [1:0]                s_arm_bresp,
    output wire                      s_arm_bvalid,
    input  wire                      s_arm_bready,

    input  wire [AXI_ADDR_WIDTH-1:0] s_arm_araddr,
    input  wire [2:0]                s_arm_arprot,
    input  wire                      s_arm_arvalid,
    output wire                      s_arm_arready,

    output wire [AXI_DATA_WIDTH-1:0] s_arm_rdata,
    output wire [1:0]                s_arm_rresp,
    output wire                      s_arm_rvalid,
    input  wire                      s_arm_rready,

    // Interrupts & Debug
    output wire                      irq_arm,   // Signal to ARM PS (IRQ_F2P)
    output wire                      irq_rv32,  // Signal when SD transfer done
    output wire [31:0]               pc_debug   // Program Counter for verification
);

    // =========================================================================
    // RV32I Core Memory Bus Wires
    // =========================================================================
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire        mem_write;
    wire        mem_read;
    wire [31:0] ext_mem_rdata;

    // =========================================================================
    // 1. RV32I Core Datapath Instance
    // =========================================================================
    Datapath cpu (
        .clk           (clk),
        .reset         (reset),
        .pcRegister    (pc_debug),
        .mem_addr      (mem_addr),
        .mem_wdata     (mem_wdata),
        .mem_write     (mem_write),
        .mem_read      (mem_read),
        .ext_mem_rdata (ext_mem_rdata)
    );

    // =========================================================================
    // 2. Dual-Port SD Mailbox Instance
    // =========================================================================
    axi_dual_sd_mailbox #(
        .DATA_WIDTH(AXI_DATA_WIDTH),
        .ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) mailbox (
        .clk           (clk),
        .rst_n         (~reset),

        // Port A: ARM Cortex-A9 (AXI4-Lite)
        .s_arm_awaddr  (s_arm_awaddr),
        .s_arm_awprot  (s_arm_awprot),
        .s_arm_awvalid (s_arm_awvalid),
        .s_arm_awready (s_arm_awready),
        .s_arm_wdata   (s_arm_wdata),
        .s_arm_wstrb   (s_arm_wstrb),
        .s_arm_wvalid  (s_arm_wvalid),
        .s_arm_wready  (s_arm_wready),
        .s_arm_bresp   (s_arm_bresp),
        .s_arm_bvalid  (s_arm_bvalid),
        .s_arm_bready  (s_arm_bready),
        .s_arm_araddr  (s_arm_araddr),
        .s_arm_arprot  (s_arm_arprot),
        .s_arm_arvalid (s_arm_arvalid),
        .s_arm_arready (s_arm_arready),
        .s_arm_rdata   (s_arm_rdata),
        .s_arm_rresp   (s_arm_rresp),
        .s_arm_rvalid  (s_arm_rvalid),
        .s_arm_rready  (s_arm_rready),

        // Port B: Direct RV32 Core Memory Bus
        .s_rv32_addr   (mem_addr[AXI_ADDR_WIDTH-1:0]),
        .s_rv32_wdata  (mem_wdata),
        .s_rv32_write  (mem_write),
        .s_rv32_read   (mem_read),
        .s_rv32_rdata  (ext_mem_rdata),

        .irq_arm       (irq_arm),
        .irq_rv32      (irq_rv32)
    );

endmodule

