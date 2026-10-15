`timescale 1ns / 1ps

module tb_axi_sd_mailbox;

    reg         clk;
    reg         rst_n;

    // AXI4-Lite signals
    reg  [11:0] s_axi_awaddr;
    reg  [2:0]  s_axi_awprot;
    reg         s_axi_awvalid;
    wire        s_axi_awready;

    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;

    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;

    reg  [11:0] s_axi_araddr;
    reg  [2:0]  s_axi_arprot;
    reg         s_axi_arvalid;
    wire        s_axi_arready;

    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;

    wire        irq_arm;
    wire        irq_rv32;

    // Instantiate UUT
    axi_sd_mailbox #(
        .C_S_AXI_DATA_WIDTH(32),
        .C_S_AXI_ADDR_WIDTH(12)
    ) uut (
        .s_axi_aclk    (clk),
        .s_axi_aresetn (rst_n),

        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awprot  (s_axi_awprot),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),

        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),

        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),

        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arprot  (s_axi_arprot),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),

        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),

        .irq_arm       (irq_arm),
        .irq_rv32      (irq_rv32)
    );

    // Clock generation (100 MHz = 10ns period)
    always #5 clk = ~clk;

    // AXI Write Task
    task axi_write(input [11:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axi_awaddr  <= addr;
            s_axi_awprot  <= 3'b000;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wstrb   <= 4'b1111;
            s_axi_wvalid  <= 1'b1;
            s_axi_bready  <= 1'b1;

            // Wait for both address and data handshakes
            fork
                begin
                    while (!s_axi_awready) @(posedge clk);
                    @(posedge clk);
                    s_axi_awvalid <= 1'b0;
                end
                begin
                    while (!s_axi_wready) @(posedge clk);
                    @(posedge clk);
                    s_axi_wvalid <= 1'b0;
                end
            join

            // Wait for write response
            while (!s_axi_bvalid) @(posedge clk);
            @(posedge clk);
            s_axi_bready <= 1'b0;
            @(posedge clk);
        end
    endtask

    // AXI Read Task
    task axi_read(input [11:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            s_axi_araddr  <= addr;
            s_axi_arprot  <= 3'b000;
            s_axi_arvalid <= 1'b1;
            s_axi_rready  <= 1'b1;

            while (!s_axi_arready) @(posedge clk);
            @(posedge clk);
            s_axi_arvalid <= 1'b0;

            while (!s_axi_rvalid) @(posedge clk);
            data = s_axi_rdata;
            @(posedge clk);
            s_axi_rready <= 1'b0;
            @(posedge clk);
        end
    endtask

    integer i;
    reg [31:0] rdata;
    integer errors = 0;

    initial begin
        clk           = 0;
        rst_n         = 0;
        s_axi_awaddr  = 0;
        s_axi_awprot  = 0;
        s_axi_awvalid = 0;
        s_axi_wdata   = 0;
        s_axi_wstrb   = 0;
        s_axi_wvalid  = 0;
        s_axi_bready  = 0;
        s_axi_araddr  = 0;
        s_axi_arprot  = 0;
        s_axi_arvalid = 0;
        s_axi_rready  = 0;

        // Apply Reset
        #20;
        @(posedge clk);
        rst_n = 1;
        #20;

        $display("=== TEST 1: Check Read-Only Identification Registers ===");
        axi_read(12'h018, rdata);
        if (rdata !== 32'h53444D42) begin
            $display("[FAIL] Signature mismatch: expected 0x53444D42 ('SDMB'), got 0x%08X", rdata);
            errors = errors + 1;
        end else begin
            $display("[PASS] Signature matched: 0x%08X ('SDMB')", rdata);
        end

        axi_read(12'h014, rdata);
        if (rdata !== 32'd512) begin
            $display("[FAIL] Sector size mismatch: expected 512, got %0d", rdata);
            errors = errors + 1;
        end else begin
            $display("[PASS] Sector size matched: %0d bytes", rdata);
        end

        $display("=== TEST 2: Register Write & Read-Back ===");
        axi_write(12'h000, 32'h00000001); // COMMAND = 1 (READ)
        axi_write(12'h004, 32'h00000064); // ADDRESS = 100 (Sector 100)
        axi_write(12'h008, 32'h00000003); // CONTROL = REQ | IRQ_ARM_EN

        axi_read(12'h000, rdata);
        if (rdata !== 32'd1) begin errors = errors + 1; $display("[FAIL] COMMAND mismatch"); end

        axi_read(12'h004, rdata);
        if (rdata !== 32'd100) begin errors = errors + 1; $display("[FAIL] ADDRESS mismatch"); end

        axi_read(12'h008, rdata);
        if (rdata !== 32'd3) begin errors = errors + 1; $display("[FAIL] CONTROL mismatch"); end

        if (irq_arm !== 1'b1) begin
            $display("[FAIL] irq_arm expected to be asserted!");
            errors = errors + 1;
        end else begin
            $display("[PASS] irq_arm asserted correctly on REQ with IRQ_ARM_EN");
        end

        $display("=== TEST 3: Buffer RAM Write and Read (512 Bytes / 128 Words) ===");
        for (i = 0; i < 128; i = i + 1) begin
            axi_write(12'h020 + (i * 4), 32'hA0000000 + i);
        end

        for (i = 0; i < 128; i = i + 1) begin
            axi_read(12'h020 + (i * 4), rdata);
            if (rdata !== (32'hA0000000 + i)) begin
                $display("[FAIL] Buffer word %0d mismatch: expected 0x%08X, got 0x%08X", i, 32'hA0000000 + i, rdata);
                errors = errors + 1;
            end
        end
        if (errors == 0) $display("[PASS] All 128 words in 512B buffer verified successfully");

        $display("=== TEST 4: Emulate RV32 <-> ARM Handshake Workflow ===");
        // 1. RV32 requests sector 2048 read
        axi_write(12'h004, 32'd2048);      // ADDRESS = 2048
        axi_write(12'h000, 32'd1);         // COMMAND = READ
        axi_write(12'h008, 32'd5);         // CONTROL = REQ | IRQ_RV32_EN

        // 2. ARM server polls and detects REQ
        axi_read(12'h008, rdata);
        if ((rdata & 32'd1) != 1) begin
            $display("[FAIL] ARM did not see REQ bit!");
            errors = errors + 1;
        end else begin
            $display("[PASS] ARM detected REQ from RV32");
        end

        // 3. ARM acknowledges and marks BUSY
        axi_write(12'h00C, 32'd1); // STATUS = BUSY
        axi_write(12'h008, 32'd4); // Clear REQ, keep IRQ_RV32_EN

        // 4. ARM writes simulated sector data (e.g. MBR boot signature 0x55AA at word 127)
        axi_write(12'h020, 32'hEB589000);        // Word 0 (Jump boot code)
        axi_write(12'h21C, 32'hAA550000);        // Word 127 (Contains 0x55AA signature)

        // 5. ARM marks DONE
        axi_write(12'h010, 32'd0); // ERROR = 0
        axi_write(12'h00C, 32'd2); // STATUS = DONE

        // Check if irq_rv32 asserted
        #10;
        if (irq_rv32 !== 1'b1) begin
            $display("[FAIL] irq_rv32 expected to be asserted on DONE!");
            errors = errors + 1;
        end else begin
            $display("[PASS] irq_rv32 asserted on DONE");
        end

        // 6. RV32 reads STATUS and reads data
        axi_read(12'h00C, rdata);
        if (rdata !== 32'd2) begin
            $display("[FAIL] RV32 did not see DONE status!");
            errors = errors + 1;
        end else begin
            $display("[PASS] RV32 observed DONE status");
        end

        axi_read(12'h020, rdata);
        if (rdata !== 32'hEB589000) begin errors = errors + 1; $display("[FAIL] Word 0 mismatch"); end

        axi_read(12'h21C, rdata);
        if (rdata !== 32'hAA550000) begin errors = errors + 1; $display("[FAIL] Word 127 mismatch"); end

        // RV32 returns STATUS to IDLE
        axi_write(12'h00C, 32'd0);
        #10;
        if (irq_rv32 !== 1'b0) begin
            $display("[FAIL] irq_rv32 should deassert when STATUS returned to IDLE!");
            errors = errors + 1;
        end else begin
            $display("[PASS] Handshake cycle completed cleanly!");
        end

        $display("=================================================");
        if (errors == 0) begin
            $display(">>> ALL SIMULATION TESTS PASSED SUCCESSFULLY! <<<");
        end else begin
            $display(">>> SIMULATION COMPLETED WITH %0d ERRORS! <<<", errors);
        end
        $display("=================================================");

        #50;
        $finish;
    end

endmodule

