// ============================================================================
// Module: rv32_to_axi_lite
// Description: Bridges simple single-cycle CPU memory bus (addr, wdata, write, read)
//              to standard AXI4-Lite Master transactions.
// ============================================================================

`timescale 1ns / 1ps

module rv32_to_axi_lite #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  reset,

    // CPU Memory Bus Interface
    input  wire [31:0]           cpu_addr,
    input  wire [31:0]           cpu_wdata,
    input  wire                  cpu_write,
    input  wire                  cpu_read,
    output reg  [31:0]           cpu_rdata,

    // AXI4-Lite Master Interface
    output reg  [ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [2:0]            m_axi_awprot,
    output reg                   m_axi_awvalid,
    input  wire                  m_axi_awready,

    output reg  [DATA_WIDTH-1:0] m_axi_wdata,
    output wire [3:0]            m_axi_wstrb,
    output reg                   m_axi_wvalid,
    input  wire                  m_axi_wready,

    input  wire [1:0]            m_axi_bresp,
    input  wire                  m_axi_bvalid,
    output reg                   m_axi_bready,

    output reg  [ADDR_WIDTH-1:0] m_axi_araddr,
    output wire [2:0]            m_axi_arprot,
    output reg                   m_axi_arvalid,
    input  wire                  m_axi_arready,

    input  wire [DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]            m_axi_rresp,
    input  wire                  m_axi_rvalid,
    output reg                   m_axi_rready
);

    assign m_axi_awprot = 3'b000;
    assign m_axi_arprot = 3'b000;
    assign m_axi_wstrb  = 4'b1111;

    // Write Channel Logic
    always @(posedge clk) begin
        if (reset) begin
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
            m_axi_awaddr  <= 0;
            m_axi_wdata   <= 0;
        end else begin
            if (cpu_write && !m_axi_awvalid && !m_axi_bvalid) begin
                m_axi_awaddr  <= cpu_addr[ADDR_WIDTH-1:0];
                m_axi_wdata   <= cpu_wdata;
                m_axi_awvalid <= 1'b1;
                m_axi_wvalid  <= 1'b1;
                m_axi_bready  <= 1'b1;
            end

            if (m_axi_awready && m_axi_awvalid) m_axi_awvalid <= 1'b0;
            if (m_axi_wready && m_axi_wvalid)   m_axi_wvalid  <= 1'b0;

            if (m_axi_bvalid && m_axi_bready)   m_axi_bready  <= 1'b0;
        end
    end

    // Read Channel Logic
    always @(posedge clk) begin
        if (reset) begin
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b0;
            m_axi_araddr  <= 0;
            cpu_rdata     <= 32'd0;
        end else begin
            if (cpu_read && !m_axi_arvalid && !m_axi_rvalid) begin
                m_axi_araddr  <= cpu_addr[ADDR_WIDTH-1:0];
                m_axi_arvalid <= 1'b1;
                m_axi_rready  <= 1'b1;
            end

            if (m_axi_arready && m_axi_arvalid) m_axi_arvalid <= 1'b0;

            if (m_axi_rvalid && m_axi_rready) begin
                cpu_rdata    <= m_axi_rdata;
                m_axi_rready <= 1'b0;
            end
        end
    end

endmodule

