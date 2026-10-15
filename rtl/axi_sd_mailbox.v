// ============================================================================
// Module: axi_sd_mailbox
// Description: AXI4-Lite Shared Mailbox Peripheral for SD Card Sector Transfers
//              Allows custom PL processor (e.g., RV32) and PS (ARM Cortex-A9)
//              to coordinate SD card sector transfers.
//
// Register Map (Base offset):
//   0x000: SD_COMMAND      (R/W) 1 = Read Sector, 2 = Write Sector
//   0x004: SD_ADDRESS      (R/W) 32-bit Sector Number (LBA)
//   0x008: SD_CONTROL      (R/W) Bit 0: REQ (1 = Request Pending)
//                                Bit 1: IRQ_ARM_EN (1 = Interrupt ARM on REQ)
//                                Bit 2: IRQ_RV32_EN (1 = Interrupt RV32 on DONE/ERR)
//   0x00C: SD_STATUS       (R/W) 0 = IDLE, 1 = BUSY, 2 = DONE, 3 = ERROR
//   0x010: SD_ERROR        (R/W) Error code (0 = SUCCESS, >0 = error)
//   0x014: SD_SECTOR_SIZE  (RO)  Fixed at 512 (bytes)
//   0x018: SD_SIGNATURE    (RO)  0x53444D42 ("SDMB" in ASCII)
//   0x020 - 0x21C:
//          SD_DATA[0..127] (R/W) 512-Byte Sector Buffer (128 x 32-bit words)
// ============================================================================

`timescale 1ns / 1ps

module axi_sd_mailbox #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 12
)(
    // AXI4-Lite Clock and Reset
    input  wire                              s_axi_aclk,
    input  wire                              s_axi_aresetn,

    // AXI4-Lite Write Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire [2:0]                        s_axi_awprot,
    input  wire                              s_axi_awvalid,
    output reg                               s_axi_awready,

    // AXI4-Lite Write Data Channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                              s_axi_wvalid,
    output reg                               s_axi_wready,

    // AXI4-Lite Write Response Channel
    output reg  [1:0]                        s_axi_bresp,
    output reg                               s_axi_bvalid,
    input  wire                              s_axi_bready,

    // AXI4-Lite Read Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire [2:0]                        s_axi_arprot,
    input  wire                              s_axi_arvalid,
    output reg                               s_axi_arready,

    // AXI4-Lite Read Data Channel
    output reg  [C_S_AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output reg  [1:0]                        s_axi_rresp,
    output reg                               s_axi_rvalid,
    input  wire                              s_axi_rready,

    // Optional Interrupt Outputs
    output wire                              irq_arm,   // Triggered when RV32 requests operation
    output wire                              irq_rv32   // Triggered when operation completed
);

    // =========================================================================
    // Register Offsets & Constants
    // =========================================================================
    localparam [11:0] ADDR_COMMAND     = 12'h000;
    localparam [11:0] ADDR_ADDRESS     = 12'h004;
    localparam [11:0] ADDR_CONTROL     = 12'h008;
    localparam [11:0] ADDR_STATUS      = 12'h00C;
    localparam [11:0] ADDR_ERROR       = 12'h010;
    localparam [11:0] ADDR_SECTOR_SIZE = 12'h014;
    localparam [11:0] ADDR_SIGNATURE   = 12'h018;
    localparam [11:0] ADDR_BUFFER_BASE = 12'h020;
    localparam [11:0] ADDR_BUFFER_END  = 12'h21C;

    localparam [31:0] SIGNATURE_VAL    = 32'h53444D42; // "SDMB"
    localparam [31:0] SECTOR_SIZE_VAL  = 32'd512;

    // =========================================================================
    // Internal Registers and 512-Byte Buffer RAM
    // =========================================================================
    reg [31:0] reg_command;
    reg [31:0] reg_address;
    reg [31:0] reg_control;
    reg [31:0] reg_status;
    reg [31:0] reg_error;

    // 128 x 32-bit words = 512 bytes of sector buffer memory
    // Split into 4 byte lanes to support byte write strobes cleanly
    reg [7:0] ram_byte0 [0:127];
    reg [7:0] ram_byte1 [0:127];
    reg [7:0] ram_byte2 [0:127];
    reg [7:0] ram_byte3 [0:127];

    // =========================================================================
    // Interrupt Generation
    // =========================================================================
    // reg_control[0]: REQ
    // reg_control[1]: IRQ_ARM_EN
    // reg_control[2]: IRQ_RV32_EN
    assign irq_arm  = reg_control[1] & reg_control[0];
    assign irq_rv32 = reg_control[2] & ((reg_status == 32'd2) | (reg_status == 32'd3));

    // =========================================================================
    // AXI-Lite Write Transaction Handling
    // =========================================================================
    reg [C_S_AXI_ADDR_WIDTH-1:0] write_addr;
    reg                          write_addr_valid;
    reg [C_S_AXI_DATA_WIDTH-1:0] write_data;
    reg [(C_S_AXI_DATA_WIDTH/8)-1:0] write_strb;
    reg                          write_data_valid;

    wire [6:0] write_buffer_idx = (write_addr[8:2] - 7'd8);
    wire       write_is_buffer  = (write_addr >= ADDR_BUFFER_BASE && write_addr <= ADDR_BUFFER_END);

    // Write address handshake
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_awready    <= 1'b0;
            write_addr_valid <= 1'b0;
            write_addr       <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            if (s_axi_awvalid && !s_axi_awready && !write_addr_valid) begin
                s_axi_awready    <= 1'b1;
                write_addr_valid <= 1'b1;
                write_addr       <= s_axi_awaddr;
            end else begin
                s_axi_awready <= 1'b0;
                if (s_axi_bvalid && s_axi_bready) begin
                    write_addr_valid <= 1'b0;
                end
            end
        end
    end

    // Write data handshake
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_wready     <= 1'b0;
            write_data_valid <= 1'b0;
            write_data       <= {C_S_AXI_DATA_WIDTH{1'b0}};
            write_strb       <= {(C_S_AXI_DATA_WIDTH/8){1'b0}};
        end else begin
            if (s_axi_wvalid && !s_axi_wready && !write_data_valid) begin
                s_axi_wready     <= 1'b1;
                write_data_valid <= 1'b1;
                write_data       <= s_axi_wdata;
                write_strb       <= s_axi_wstrb;
            end else begin
                s_axi_wready <= 1'b0;
                if (s_axi_bvalid && s_axi_bready) begin
                    write_data_valid <= 1'b0;
                end
            end
        end
    end

    // Write execution and response
    integer i;
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= 2'b00; // OKAY
            reg_command  <= 32'd0;
            reg_address  <= 32'd0;
            reg_control  <= 32'd0;
            reg_status   <= 32'd0; // IDLE
            reg_error    <= 32'd0;
            for (i = 0; i < 128; i = i + 1) begin
                ram_byte0[i] <= 8'h00;
                ram_byte1[i] <= 8'h00;
                ram_byte2[i] <= 8'h00;
                ram_byte3[i] <= 8'h00;
            end
        end else begin
            if (write_addr_valid && write_data_valid && !s_axi_bvalid) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00; // OKAY

                if (write_is_buffer) begin
                    if (write_strb[0]) ram_byte0[write_buffer_idx] <= write_data[7:0];
                    if (write_strb[1]) ram_byte1[write_buffer_idx] <= write_data[15:8];
                    if (write_strb[2]) ram_byte2[write_buffer_idx] <= write_data[23:16];
                    if (write_strb[3]) ram_byte3[write_buffer_idx] <= write_data[31:24];
                end else begin
                    case (write_addr[11:0])
                        ADDR_COMMAND: begin
                            if (write_strb[0]) reg_command[7:0]   <= write_data[7:0];
                            if (write_strb[1]) reg_command[15:8]  <= write_data[15:8];
                            if (write_strb[2]) reg_command[23:16] <= write_data[23:16];
                            if (write_strb[3]) reg_command[31:24] <= write_data[31:24];
                        end
                        ADDR_ADDRESS: begin
                            if (write_strb[0]) reg_address[7:0]   <= write_data[7:0];
                            if (write_strb[1]) reg_address[15:8]  <= write_data[15:8];
                            if (write_strb[2]) reg_address[23:16] <= write_data[23:16];
                            if (write_strb[3]) reg_address[31:24] <= write_data[31:24];
                        end
                        ADDR_CONTROL: begin
                            if (write_strb[0]) reg_control[7:0]   <= write_data[7:0];
                            if (write_strb[1]) reg_control[15:8]  <= write_data[15:8];
                            if (write_strb[2]) reg_control[23:16] <= write_data[23:16];
                            if (write_strb[3]) reg_control[31:24] <= write_data[31:24];
                        end
                        ADDR_STATUS: begin
                            if (write_strb[0]) reg_status[7:0]   <= write_data[7:0];
                            if (write_strb[1]) reg_status[15:8]  <= write_data[15:8];
                            if (write_strb[2]) reg_status[23:16] <= write_data[23:16];
                            if (write_strb[3]) reg_status[31:24] <= write_data[31:24];
                        end
                        ADDR_ERROR: begin
                            if (write_strb[0]) reg_error[7:0]   <= write_data[7:0];
                            if (write_strb[1]) reg_error[15:8]  <= write_data[15:8];
                            if (write_strb[2]) reg_error[23:16] <= write_data[23:16];
                            if (write_strb[3]) reg_error[31:24] <= write_data[31:24];
                        end
                        default: begin
                            // Read-only registers or unmapped offsets ignore writes
                        end
                    endcase
                end
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // AXI-Lite Read Transaction Handling
    // =========================================================================
    reg [C_S_AXI_ADDR_WIDTH-1:0] read_addr;
    wire [6:0] read_buffer_idx = (read_addr[8:2] - 7'd8);
    wire       read_is_buffer  = (read_addr >= ADDR_BUFFER_BASE && read_addr <= ADDR_BUFFER_END);

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00; // OKAY
            s_axi_rdata   <= 32'd0;
            read_addr     <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            // Address handshake
            if (s_axi_arvalid && !s_axi_arready && !s_axi_rvalid) begin
                s_axi_arready <= 1'b1;
                read_addr     <= s_axi_araddr;
            end else begin
                s_axi_arready <= 1'b0;
            end

            // Data response generation (1 cycle after address accepted)
            if (s_axi_arready) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00; // OKAY

                if (read_is_buffer) begin
                    s_axi_rdata <= {
                        ram_byte3[read_buffer_idx],
                        ram_byte2[read_buffer_idx],
                        ram_byte1[read_buffer_idx],
                        ram_byte0[read_buffer_idx]
                    };
                end else begin
                    case (read_addr[11:0])
                        ADDR_COMMAND:     s_axi_rdata <= reg_command;
                        ADDR_ADDRESS:     s_axi_rdata <= reg_address;
                        ADDR_CONTROL:     s_axi_rdata <= reg_control;
                        ADDR_STATUS:      s_axi_rdata <= reg_status;
                        ADDR_ERROR:       s_axi_rdata <= reg_error;
                        ADDR_SECTOR_SIZE: s_axi_rdata <= SECTOR_SIZE_VAL;
                        ADDR_SIGNATURE:   s_axi_rdata <= SIGNATURE_VAL;
                        default:          s_axi_rdata <= 32'h00000000;
                    endcase
                end
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule

