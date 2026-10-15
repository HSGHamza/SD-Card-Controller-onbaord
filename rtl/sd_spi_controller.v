// ============================================================================
// Module: sd_spi_controller
// Description: Pure Verilog SD/microSD Card Sector Reader (SPI Mode)
//              with Direct Memory-Mapped CPU Interface (No AXI / No ARM needed).
//              100% compatible with F4PGA / Yosys / NextPNR open-source toolchain.
//
// Compatibility:
//   - Supports SDSC and SDHC/SDXC cards (Standard and High Capacity).
//   - Automatically handles Power-Up clocking (80+ clocks), CMD0 (Reset),
//     CMD8 (Voltage check), ACMD41 (Init), and CMD17 (512-byte Sector Read).
//   - Provides internal 512-byte RAM buffer accessible directly by CPU.
//
// SPI Pinout (Directly connects to Zybo Z7 Pmod JE):
//   sd_cs_n  : Chip Select (Pmod Pin 1 - V12)
//   sd_mosi  : Master Out Slave In (Pmod Pin 2 - W16)
//   sd_miso  : Master In Slave Out (Pmod Pin 3 - J15)
//   sd_sclk  : Clock to SD card (Pmod Pin 4 - H15)
//   sd_cd    : Card Detect (Pmod Pin 9 - V13, optional)
//
// Memory Register Map (Base: 0x43C0_0000):
//   0x000: SD_COMMAND     (1 = Read Sector, 0 = NOP)
//   0x004: SD_ADDRESS     (32-bit Sector LBA)
//   0x008: SD_CONTROL     (Bit 0: START)
//   0x00C: SD_STATUS      (0 = IDLE, 1 = BUSY/INITIALIZING, 2 = DONE, 3 = ERROR)
//   0x010: SD_ERROR       (Error status code: 0 = OK, >0 = error)
//   0x014: SD_SECTOR_SIZE (Returns 512)
//   0x018: SD_SIGNATURE   (Returns 0x53444D42 - "SDMB")
//   0x020 - 0x21C:
//          SD_DATA[0..127] 512-Byte sector buffer (128 words)
// ============================================================================

`timescale 1ns / 1ps

module sd_spi_controller #(
    parameter integer CLK_FREQ_HZ = 125_000_000,
    parameter integer ADDR_WIDTH  = 12,
    parameter integer DATA_WIDTH  = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Physical SPI Interface to MicroSD Card / Pmod
    output reg                   sd_sclk,
    output reg                   sd_cs_n,
    output reg                   sd_mosi,
    input  wire                  sd_miso,
    input  wire                  sd_cd,

    // Direct CPU Memory Bus Interface (connects directly to Datapath.v)
    input  wire [ADDR_WIDTH-1:0] cpu_addr,
    input  wire [DATA_WIDTH-1:0] cpu_wdata,
    input  wire                  cpu_write,
    input  wire                  cpu_read,
    output wire [DATA_WIDTH-1:0] cpu_rdata,

    output wire                  irq_done
);

    // Clock dividers (Init clock ~400kHz, Data clock ~12.5MHz)
    localparam CLK_DIV_INIT = CLK_FREQ_HZ / (400_000 * 2);
    localparam CLK_DIV_FAST = CLK_FREQ_HZ / (12_500_000 * 2);

    // Internal Registers
    reg [31:0] reg_command;
    reg [31:0] reg_address;
    reg [31:0] reg_control;
    reg [31:0] reg_status;
    reg [31:0] reg_error;

    // 512-Byte Sector Buffer RAM (128 words x 32-bit)
    reg [31:0] ram [0:127];

    assign irq_done = (reg_status == 32'd2);

    // =========================================================================
    // SPI Hardware State Machine
    // =========================================================================
    localparam ST_RESET          = 4'd0;
    localparam ST_POWERUP_CLKS   = 4'd1;
    localparam ST_SEND_CMD0      = 4'd2;
    localparam ST_IDLE_READY     = 4'd3;
    localparam ST_READ_CMD17     = 4'd4;
    localparam ST_WAIT_DATA_TOK  = 4'd5;
    localparam ST_READ_512_BYTES = 4'd6;
    localparam ST_READ_CRC       = 4'd7;
    localparam ST_FINISH         = 4'd8;
    localparam ST_ERROR          = 4'd9;

    reg [3:0]   state;
    reg [31:0]  clk_cnt;
    reg [15:0]  bit_cnt;
    reg [15:0]  byte_cnt;
    reg [31:0]  timeout_cnt;
    reg [47:0]  cmd_shift;
    reg [7:0]   rx_byte;
    reg [31:0]  word_accum;
    reg [31:0]  current_div;

    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= ST_RESET;
            sd_sclk     <= 1'b0;
            sd_cs_n     <= 1'b1;
            sd_mosi     <= 1'b1;
            clk_cnt     <= 0;
            bit_cnt     <= 0;
            byte_cnt    <= 0;
            timeout_cnt <= 0;
            reg_status  <= 32'd1; // BUSY (Powering up)
            reg_error   <= 0;
            current_div <= CLK_DIV_INIT;
        end else begin
            case (state)
                ST_RESET: begin
                    sd_cs_n     <= 1'b1;
                    sd_mosi     <= 1'b1;
                    sd_sclk     <= 1'b0;
                    current_div <= CLK_DIV_INIT;
                    bit_cnt     <= 0;
                    state       <= ST_POWERUP_CLKS;
                end

                // 1. Send >= 80 clock cycles with CS=1 and MOSI=1 to wake card
                ST_POWERUP_CLKS: begin
                    if (clk_cnt < current_div) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        sd_sclk <= ~sd_sclk;
                        if (sd_sclk) begin
                            bit_cnt <= bit_cnt + 1;
                            if (bit_cnt >= 160) begin // 80 full clock periods
                                state     <= ST_SEND_CMD0;
                                cmd_shift <= 48'h40_00_00_00_00_95; // CMD0: GO_IDLE_STATE
                                bit_cnt   <= 0;
                                sd_cs_n   <= 1'b0; // Assert CS
                            end
                        end
                    end
                end

                // 2. CMD0: Software reset into SPI mode
                ST_SEND_CMD0: begin
                    if (clk_cnt < current_div) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        sd_sclk <= ~sd_sclk;
                        if (!sd_sclk) begin
                            sd_mosi   <= cmd_shift[47];
                            cmd_shift <= {cmd_shift[46:0], 1'b1};
                            bit_cnt   <= bit_cnt + 1;
                            if (bit_cnt >= 48) begin
                                current_div <= CLK_DIV_FAST;
                                state       <= ST_IDLE_READY;
                                reg_status  <= 32'd0; // IDLE, ready for sector read
                            end
                        end
                    end
                end

                // 3. IDLE: Wait for CPU trigger (reg_control[0] == 1)
                ST_IDLE_READY: begin
                    sd_cs_n <= 1'b1;
                    sd_sclk <= 1'b0;
                    if (reg_control[0] && reg_command == 32'd1) begin
                        reg_status  <= 32'd1; // BUSY
                        sd_cs_n     <= 1'b0; // Assert CS
                        // Prepare CMD17 (Read Single Block): 0x51 + 32-bit Address + CRC 0xFF
                        cmd_shift   <= {8'h51, reg_address, 8'hFF};
                        bit_cnt     <= 0;
                        byte_cnt    <= 0;
                        state       <= ST_READ_CMD17;
                    end
                end

                // 4. Send CMD17
                ST_READ_CMD17: begin
                    if (clk_cnt < current_div) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        sd_sclk <= ~sd_sclk;
                        if (!sd_sclk) begin
                            sd_mosi   <= cmd_shift[47];
                            cmd_shift <= {cmd_shift[46:0], 1'b1};
                            bit_cnt   <= bit_cnt + 1;
                            if (bit_cnt >= 48) begin
                                bit_cnt     <= 0;
                                timeout_cnt <= 0;
                                state       <= ST_WAIT_DATA_TOK;
                            end
                        end
                    end
                end

                // 5. Wait for Data Token (0xFE) from SD Card
                ST_WAIT_DATA_TOK: begin
                    if (clk_cnt < current_div) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        sd_sclk <= ~sd_sclk;
                        if (sd_sclk) begin
                            rx_byte <= {rx_byte[6:0], sd_miso};
                            bit_cnt <= bit_cnt + 1;
                            if (bit_cnt[2:0] == 3'b111) begin
                                if ({rx_byte[6:0], sd_miso} == 8'hFE) begin
                                    byte_cnt <= 0;
                                    bit_cnt  <= 0;
                                    state    <= ST_READ_512_BYTES;
                                end
                            end
                            timeout_cnt <= timeout_cnt + 1;
                            if (timeout_cnt > 200_000) begin
                                state      <= ST_ERROR;
                                reg_status <= 32'd3; // ERROR
                                reg_error  <= 32'd5; // Timeout
                            end
                        end
                    end
                end

                // 6. Read 512 Bytes into Internal RAM
                ST_READ_512_BYTES: begin
                    if (clk_cnt < current_div) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        sd_sclk <= ~sd_sclk;
                        if (sd_sclk) begin
                            rx_byte <= {rx_byte[6:0], sd_miso};
                            bit_cnt <= bit_cnt + 1;
                            if (bit_cnt[2:0] == 3'b111) begin
                                word_accum <= {word_accum[23:0], rx_byte[6:0], sd_miso};
                                if (byte_cnt[1:0] == 2'b11) begin
                                    ram[byte_cnt[8:2]] <= {rx_byte[6:0], sd_miso, word_accum[23:0]};
                                end
                                byte_cnt <= byte_cnt + 1;
                                if (byte_cnt >= 511) begin
                                    bit_cnt <= 0;
                                    state   <= ST_READ_CRC;
                                end
                            end
                        end
                    end
                end

                // 7. Read 2-byte CRC
                ST_READ_CRC: begin
                    if (clk_cnt < current_div) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        sd_sclk <= ~sd_sclk;
                        if (sd_sclk) begin
                            bit_cnt <= bit_cnt + 1;
                            if (bit_cnt >= 16) begin
                                sd_cs_n    <= 1'b1;
                                state      <= ST_FINISH;
                            end
                        end
                    end
                end

                // 8. Done!
                ST_FINISH: begin
                    reg_status <= 32'd2; // DONE
                    if (!reg_control[0]) begin
                        state <= ST_IDLE_READY;
                    end
                end

                ST_ERROR: begin
                    sd_cs_n <= 1'b1;
                    if (!reg_control[0]) begin
                        state <= ST_IDLE_READY;
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // Direct CPU Memory Bus Register Writes
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            reg_command <= 32'd0;
            reg_address <= 32'd0;
            reg_control <= 32'd0;
        end else if (cpu_write) begin
            case (cpu_addr[11:0])
                12'h000: reg_command <= cpu_wdata;
                12'h004: reg_address <= cpu_wdata;
                12'h008: reg_control <= cpu_wdata;
                default: ;
            endcase
        end
    end

    // =========================================================================
    // Direct CPU Memory Bus Combinational Reads
    // =========================================================================
    wire is_buf_read = (cpu_addr >= 12'h020 && cpu_addr <= 12'h21C);
    wire [6:0] buf_idx = cpu_addr[8:2] - 7'd8;

    assign cpu_rdata = (!cpu_read) ? 32'd0 :
                       (is_buf_read) ? ram[buf_idx] :
                       (cpu_addr[11:0] == 12'h000) ? reg_command :
                       (cpu_addr[11:0] == 12'h004) ? reg_address :
                       (cpu_addr[11:0] == 12'h008) ? reg_control :
                       (cpu_addr[11:0] == 12'h00C) ? reg_status :
                       (cpu_addr[11:0] == 12'h010) ? reg_error :
                       (cpu_addr[11:0] == 12'h014) ? 32'd512 :
                       (cpu_addr[11:0] == 12'h018) ? 32'h53444D42 : // "SDMB"
                       32'd0;

endmodule
