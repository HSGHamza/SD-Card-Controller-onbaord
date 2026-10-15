// ============================================================================
// Module: axi_dual_sd_mailbox
// Description: Dual-Port AXI4-Lite Mailbox Peripheral for SD Card Transfers
//              Port A: Connects directly to ARM Cortex-A9 (PS M_AXI_GP0)
//              Port B: Connects directly to Custom RV32 Core AXI Master
//
// Features:
//   - Independent AXI4-Lite slave interfaces for ARM and RV32
//   - Eliminates need for complex Vivado multi-master AXI interconnects
//   - 512-Byte (128 x 32-bit) True Dual-Port Block RAM sector buffer
//   - Hardware synchronization & status flags between ARM and RV32
//
// Register Map (Both ports see identical addresses):
//   0x000: SD_COMMAND      [31:0] (RV32 W, ARM R) 1 = Read Sector, 2 = Write
//   0x004: SD_ADDRESS      [31:0] (RV32 W, ARM R) 32-bit Sector LBA
//   0x008: SD_CONTROL      [31:0] Bit 0: REQ (RV32 writes 1 to start)
//                                 Bit 1: IRQ_ARM_EN
//                                 Bit 2: IRQ_RV32_EN
//   0x00C: SD_STATUS       [31:0] (ARM W, RV32 R) 0=IDLE, 1=BUSY, 2=DONE, 3=ERR
//   0x010: SD_ERROR        [31:0] (ARM W, RV32 R) Error Code
//   0x014: SD_SECTOR_SIZE  [31:0] (RO) Fixed 512
//   0x018: SD_SIGNATURE    [31:0] (RO) Fixed 0x53444D42 ("SDMB")
//   0x020 - 0x21C:
//          SD_DATA[0..127] 512-Byte Sector Buffer (128 words)
// ============================================================================

`timescale 1ns / 1ps

module axi_dual_sd_mailbox #(
    parameter integer DATA_WIDTH = 32,
    parameter integer ADDR_WIDTH = 12
)(
    // Clock and Reset (Synchronous or common PL clock, e.g., FCLK_CLK0 100MHz)
    input  wire                  clk,
    input  wire                  rst_n,

    // =========================================================================
    // PORT A: ARM Cortex-A9 Interface (PS M_AXI_GP0)
    // =========================================================================
    input  wire [ADDR_WIDTH-1:0] s_arm_awaddr,
    input  wire [2:0]            s_arm_awprot,
    input  wire                  s_arm_awvalid,
    output reg                   s_arm_awready,

    input  wire [DATA_WIDTH-1:0] s_arm_wdata,
    input  wire [3:0]            s_arm_wstrb,
    input  wire                  s_arm_wvalid,
    output reg                   s_arm_wready,

    output reg  [1:0]            s_arm_bresp,
    output reg                   s_arm_bvalid,
    input  wire                  s_arm_bready,

    input  wire [ADDR_WIDTH-1:0] s_arm_araddr,
    input  wire [2:0]            s_arm_arprot,
    input  wire                  s_arm_arvalid,
    output reg                   s_arm_arready,

    output reg  [DATA_WIDTH-1:0] s_arm_rdata,
    output reg  [1:0]            s_arm_rresp,
    output reg                   s_arm_rvalid,
    input  wire                  s_arm_rready,

    // =========================================================================
    // PORT B: RV32 Core Interface (RV32 AXI Master)
    // =========================================================================
    input  wire [ADDR_WIDTH-1:0] s_rv32_awaddr,
    input  wire [2:0]            s_rv32_awprot,
    input  wire                  s_rv32_awvalid,
    output reg                   s_rv32_awready,

    input  wire [DATA_WIDTH-1:0] s_rv32_wdata,
    input  wire [3:0]            s_rv32_wstrb,
    input  wire                  s_rv32_wvalid,
    output reg                   s_rv32_wready,

    output reg  [1:0]            s_rv32_bresp,
    output reg                   s_rv32_bvalid,
    input  wire                  s_rv32_bready,

    input  wire [ADDR_WIDTH-1:0] s_rv32_araddr,
    input  wire [2:0]            s_rv32_arprot,
    input  wire                  s_rv32_arvalid,
    output reg                   s_rv32_arready,

    output reg  [DATA_WIDTH-1:0] s_rv32_rdata,
    output reg  [1:0]            s_rv32_rresp,
    output reg                   s_rv32_rvalid,
    input  wire                  s_rv32_rready,

    // =========================================================================
    // Interrupt Outputs
    // =========================================================================
    output wire                  irq_arm,   // Signals ARM when RV32 requests op
    output wire                  irq_rv32   // Signals RV32 when op is DONE/ERROR
);

    // Register Address Offsets
    localparam [11:0] ADDR_COMMAND     = 12'h000;
    localparam [11:0] ADDR_ADDRESS     = 12'h004;
    localparam [11:0] ADDR_CONTROL     = 12'h008;
    localparam [11:0] ADDR_STATUS      = 12'h00C;
    localparam [11:0] ADDR_ERROR       = 12'h010;
    localparam [11:0] ADDR_SECTOR_SIZE = 12'h014;
    localparam [11:0] ADDR_SIGNATURE   = 12'h018;
    localparam [11:0] ADDR_BUF_START   = 12'h020;
    localparam [11:0] ADDR_BUF_END     = 12'h21C;

    localparam [31:0] SIGNATURE_VAL    = 32'h53444D42; // "SDMB"
    localparam [31:0] SECTOR_SIZE_VAL  = 32'd512;

    // Registers
    reg [31:0] reg_command;
    reg [31:0] reg_address;
    reg [31:0] reg_control;
    reg [31:0] reg_status;
    reg [31:0] reg_error;

    // Interrupts
    assign irq_arm  = reg_control[1] & reg_control[0];
    assign irq_rv32 = reg_control[2] & ((reg_status == 32'd2) | (reg_status == 32'd3));

    // =========================================================================
    // 512-Byte True Dual-Port Sector Buffer (128 words x 32 bits)
    // =========================================================================
    reg [31:0] ram [0:127];

    // Helper wire for word indexing: (addr[8:2] - 8)
    wire [6:0] arm_w_idx   = s_arm_awaddr[8:2]  - 7'd8;
    wire [6:0] arm_r_idx   = s_arm_araddr[8:2]  - 7'd8;
    wire [6:0] rv32_w_idx  = s_rv32_awaddr[8:2] - 7'd8;
    wire [6:0] rv32_r_idx  = s_rv32_araddr[8:2] - 7'd8;

    wire arm_w_is_buf  = (s_arm_awaddr  >= ADDR_BUF_START && s_arm_awaddr  <= ADDR_BUF_END);
    wire arm_r_is_buf  = (s_arm_araddr  >= ADDR_BUF_START && s_arm_araddr  <= ADDR_BUF_END);
    wire rv32_w_is_buf = (s_rv32_awaddr >= ADDR_BUF_START && s_rv32_awaddr <= ADDR_BUF_END);
    wire rv32_r_is_buf = (s_rv32_araddr >= ADDR_BUF_START && s_rv32_araddr <= ADDR_BUF_END);

    // =========================================================================
    // PORT A (ARM) Write Engine
    // =========================================================================
    reg                  arm_wr_valid;
    reg [ADDR_WIDTH-1:0] arm_wr_addr;
    reg [DATA_WIDTH-1:0] arm_wr_data;
    reg [3:0]            arm_wr_strb;

    always @(posedge clk) begin
        if (!rst_n) begin
            s_arm_awready <= 1'b0;
            s_arm_wready  <= 1'b0;
            s_arm_bvalid  <= 1'b0;
            s_arm_bresp   <= 2'b00;
            arm_wr_valid  <= 1'b0;
            arm_wr_addr   <= 0;
            arm_wr_data   <= 0;
            arm_wr_strb   <= 0;
        end else begin
            // Address handshake
            if (s_arm_awvalid && !s_arm_awready) begin
                s_arm_awready <= 1'b1;
                arm_wr_addr   <= s_arm_awaddr;
            end else begin
                s_arm_awready <= 1'b0;
            end

            // Data handshake
            if (s_arm_wvalid && !s_arm_wready) begin
                s_arm_wready <= 1'b1;
                arm_wr_data  <= s_arm_wdata;
                arm_wr_strb  <= s_arm_wstrb;
            end else begin
                s_arm_wready <= 1'b0;
            end

            // Execute write
            if (s_arm_awready && s_arm_wready) begin
                arm_wr_valid <= 1'b1;
            end else begin
                arm_wr_valid <= 1'b0;
            end

            // Response
            if (arm_wr_valid && !s_arm_bvalid) begin
                s_arm_bvalid <= 1'b1;
                s_arm_bresp  <= 2'b00; // OKAY
            end else if (s_arm_bvalid && s_arm_bready) begin
                s_arm_bvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // PORT B (RV32) Write Engine
    // =========================================================================
    reg                  rv32_wr_valid;
    reg [ADDR_WIDTH-1:0] rv32_wr_addr;
    reg [DATA_WIDTH-1:0] rv32_wr_data;
    reg [3:0]            rv32_wr_strb;

    always @(posedge clk) begin
        if (!rst_n) begin
            s_rv32_awready <= 1'b0;
            s_rv32_wready  <= 1'b0;
            s_rv32_bvalid  <= 1'b0;
            s_rv32_bresp   <= 2'b00;
            rv32_wr_valid  <= 1'b0;
            rv32_wr_addr   <= 0;
            rv32_wr_data   <= 0;
            rv32_wr_strb   <= 0;
        end else begin
            if (s_rv32_awvalid && !s_rv32_awready) begin
                s_rv32_awready <= 1'b1;
                rv32_wr_addr   <= s_rv32_awaddr;
            end else begin
                s_rv32_awready <= 1'b0;
            end

            if (s_rv32_wvalid && !s_rv32_wready) begin
                s_rv32_wready <= 1'b1;
                rv32_wr_data  <= s_rv32_wdata;
                rv32_wr_strb  <= s_rv32_wstrb;
            end else begin
                s_rv32_wready <= 1'b0;
            end

            if (s_rv32_awready && s_rv32_wready) begin
                rv32_wr_valid <= 1'b1;
            end else begin
                rv32_wr_valid <= 1'b0;
            end

            if (rv32_wr_valid && !s_rv32_bvalid) begin
                s_rv32_bvalid <= 1'b1;
                s_rv32_bresp  <= 2'b00;
            end else if (s_rv32_bvalid && s_rv32_bready) begin
                s_rv32_bvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Shared Register & Buffer Write Execution
    // =========================================================================
    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            reg_command <= 32'd0;
            reg_address <= 32'd0;
            reg_control <= 32'd0;
            reg_status  <= 32'd0; // IDLE
            reg_error   <= 32'd0;
            for (i = 0; i < 128; i = i + 1) begin
                ram[i] <= 32'd0;
            end
        end else begin
            // 1. Port A (ARM) Writes: primarily writes Buffer, STATUS, ERROR, and clears REQ
            if (arm_wr_valid) begin
                if (arm_wr_addr >= ADDR_BUF_START && arm_wr_addr <= ADDR_BUF_END) begin
                    ram[arm_wr_addr[8:2] - 7'd8] <= arm_wr_data;
                end else begin
                    case (arm_wr_addr[11:0])
                        ADDR_STATUS:  reg_status  <= arm_wr_data;
                        ADDR_ERROR:   reg_error   <= arm_wr_data;
                        ADDR_CONTROL: reg_control <= arm_wr_data; // Can clear REQ bit
                        default: ;
                    endcase
                end
            end

            // 2. Port B (RV32) Writes: primarily writes COMMAND, ADDRESS, CONTROL (REQ)
            if (rv32_wr_valid) begin
                if (rv32_wr_addr >= ADDR_BUF_START && rv32_wr_addr <= ADDR_BUF_END) begin
                    ram[rv32_wr_addr[8:2] - 7'd8] <= rv32_wr_data;
                end else begin
                    case (rv32_wr_addr[11:0])
                        ADDR_COMMAND: reg_command <= rv32_wr_data;
                        ADDR_ADDRESS: reg_address <= rv32_wr_data;
                        ADDR_CONTROL: begin
                            reg_control <= rv32_wr_data;
                            // If RV32 asserts REQ bit, automatically mark STATUS = BUSY (1)
                            if (rv32_wr_data[0]) begin
                                reg_status <= 32'd1;
                            end
                        end
                        ADDR_STATUS: begin
                            // RV32 can clear STATUS to IDLE (0) after reading data
                            if (rv32_wr_data == 32'd0) reg_status <= 32'd0;
                        end
                        default: ;
                    endcase
                end
            end
        end
    end

    // =========================================================================
    // PORT A (ARM) Read Engine
    // =========================================================================
    reg [ADDR_WIDTH-1:0] arm_rd_addr;
    always @(posedge clk) begin
        if (!rst_n) begin
            s_arm_arready <= 1'b0;
            s_arm_rvalid  <= 1'b0;
            s_arm_rresp   <= 2'b00;
            s_arm_rdata   <= 32'd0;
            arm_rd_addr   <= 0;
        end else begin
            if (s_arm_arvalid && !s_arm_arready && !s_arm_rvalid) begin
                s_arm_arready <= 1'b1;
                arm_rd_addr   <= s_arm_araddr;
            end else begin
                s_arm_arready <= 1'b0;
            end

            if (s_arm_arready) begin
                s_arm_rvalid <= 1'b1;
                s_arm_rresp  <= 2'b00;
                if (arm_rd_addr >= ADDR_BUF_START && arm_rd_addr <= ADDR_BUF_END) begin
                    s_arm_rdata <= ram[arm_rd_addr[8:2] - 7'd8];
                end else begin
                    case (arm_rd_addr[11:0])
                        ADDR_COMMAND:     s_arm_rdata <= reg_command;
                        ADDR_ADDRESS:     s_arm_rdata <= reg_address;
                        ADDR_CONTROL:     s_arm_rdata <= reg_control;
                        ADDR_STATUS:      s_arm_rdata <= reg_status;
                        ADDR_ERROR:       s_arm_rdata <= reg_error;
                        ADDR_SECTOR_SIZE: s_arm_rdata <= SECTOR_SIZE_VAL;
                        ADDR_SIGNATURE:   s_arm_rdata <= SIGNATURE_VAL;
                        default:          s_arm_rdata <= 32'd0;
                    endcase
                end
            end else if (s_arm_rvalid && s_arm_rready) begin
                s_arm_rvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // PORT B (RV32) Read Engine
    // =========================================================================
    reg [ADDR_WIDTH-1:0] rv32_rd_addr;
    always @(posedge clk) begin
        if (!rst_n) begin
            s_rv32_arready <= 1'b0;
            s_rv32_rvalid  <= 1'b0;
            s_rv32_rresp   <= 2'b00;
            s_rv32_rdata   <= 32'd0;
            rv32_rd_addr   <= 0;
        end else begin
            if (s_rv32_arvalid && !s_rv32_arready && !s_rv32_rvalid) begin
                s_rv32_arready <= 1'b1;
                rv32_rd_addr   <= s_rv32_araddr;
            end else begin
                s_rv32_arready <= 1'b0;
            end

            if (s_rv32_arready) begin
                s_rv32_rvalid <= 1'b1;
                s_rv32_rresp  <= 2'b00;
                if (rv32_rd_addr >= ADDR_BUF_START && rv32_rd_addr <= ADDR_BUF_END) begin
                    s_rv32_rdata <= ram[rv32_rd_addr[8:2] - 7'd8];
                end else begin
                    case (rv32_rd_addr[11:0])
                        ADDR_COMMAND:     s_rv32_rdata <= reg_command;
                        ADDR_ADDRESS:     s_rv32_rdata <= reg_address;
                        ADDR_CONTROL:     s_rv32_rdata <= reg_control;
                        ADDR_STATUS:      s_rv32_rdata <= reg_status;
                        ADDR_ERROR:       s_rv32_rdata <= reg_error;
                        ADDR_SECTOR_SIZE: s_rv32_rdata <= SECTOR_SIZE_VAL;
                        ADDR_SIGNATURE:   s_rv32_rdata <= SIGNATURE_VAL;
                        default:          s_rv32_rdata <= 32'd0;
                    endcase
                end
            end else if (s_rv32_rvalid && s_rv32_rready) begin
                s_rv32_rvalid <= 1'b0;
            end
        end
    end

endmodule

