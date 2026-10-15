`timescale 1ns / 1ps

module tb_axi_dual_sd_mailbox;

    reg clk;
    reg rst_n;

    // ARM Port signals
    reg  [11:0] s_arm_awaddr;
    reg  [2:0]  s_arm_awprot;
    reg         s_arm_awvalid;
    wire        s_arm_awready;
    reg  [31:0] s_arm_wdata;
    reg  [3:0]  s_arm_wstrb;
    reg         s_arm_wvalid;
    wire        s_arm_wready;
    wire [1:0]  s_arm_bresp;
    wire        s_arm_bvalid;
    reg         s_arm_bready;
    reg  [11:0] s_arm_araddr;
    reg  [2:0]  s_arm_arprot;
    reg         s_arm_arvalid;
    wire        s_arm_arready;
    wire [31:0] s_arm_rdata;
    wire [1:0]  s_arm_rresp;
    wire        s_arm_rvalid;
    reg         s_arm_rready;

    // RV32 Port signals
    reg  [11:0] s_rv32_awaddr;
    reg  [2:0]  s_rv32_awprot;
    reg         s_rv32_awvalid;
    wire        s_rv32_awready;
    reg  [31:0] s_rv32_wdata;
    reg  [3:0]  s_rv32_wstrb;
    reg         s_rv32_wvalid;
    wire        s_rv32_wready;
    wire [1:0]  s_rv32_bresp;
    wire        s_rv32_bvalid;
    reg         s_rv32_bready;
    reg  [11:0] s_rv32_araddr;
    reg  [2:0]  s_rv32_arprot;
    reg         s_rv32_arvalid;
    wire        s_rv32_arready;
    wire [31:0] s_rv32_rdata;
    wire [1:0]  s_rv32_rresp;
    wire        s_rv32_rvalid;
    reg         s_rv32_rready;

    wire irq_arm;
    wire irq_rv32;

    axi_dual_sd_mailbox #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(12)
    ) uut (
        .clk           (clk),
        .rst_n         (rst_n),

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

        .s_rv32_awaddr (s_rv32_awaddr),
        .s_rv32_awprot (s_rv32_awprot),
        .s_rv32_awvalid(s_rv32_awvalid),
        .s_rv32_awready(s_rv32_awready),
        .s_rv32_wdata  (s_rv32_wdata),
        .s_rv32_wstrb  (s_rv32_wstrb),
        .s_rv32_wvalid (s_rv32_wvalid),
        .s_rv32_wready (s_rv32_wready),
        .s_rv32_bresp  (s_rv32_bresp),
        .s_rv32_bvalid (s_rv32_bvalid),
        .s_rv32_bready (s_rv32_bready),
        .s_rv32_araddr (s_rv32_araddr),
        .s_rv32_arprot (s_rv32_arprot),
        .s_rv32_arvalid(s_rv32_arvalid),
        .s_rv32_arready(s_rv32_arready),
        .s_rv32_rdata  (s_rv32_rdata),
        .s_rv32_rresp  (s_rv32_rresp),
        .s_rv32_rvalid (s_rv32_rvalid),
        .s_rv32_rready (s_rv32_rready),

        .irq_arm       (irq_arm),
        .irq_rv32      (irq_rv32)
    );

    always #5 clk = ~clk;

    // RV32 write task
    task rv32_write(input [11:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_rv32_awaddr  <= addr;
            s_rv32_awprot  <= 3'b000;
            s_rv32_awvalid <= 1'b1;
            s_rv32_wdata   <= data;
            s_rv32_wstrb   <= 4'b1111;
            s_rv32_wvalid  <= 1'b1;
            s_rv32_bready  <= 1'b1;

            fork
                begin while (!s_rv32_awready) @(posedge clk); @(posedge clk); s_rv32_awvalid <= 0; end
                begin while (!s_rv32_wready)  @(posedge clk); @(posedge clk); s_rv32_wvalid  <= 0; end
            join
            while (!s_rv32_bvalid) @(posedge clk);
            @(posedge clk);
            s_rv32_bready <= 0;
            @(posedge clk);
        end
    endtask

    // RV32 read task
    task rv32_read(input [11:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            s_rv32_araddr  <= addr;
            s_rv32_arprot  <= 3'b000;
            s_rv32_arvalid <= 1'b1;
            s_rv32_rready  <= 1'b1;
            while (!s_rv32_arready) @(posedge clk);
            @(posedge clk);
            s_rv32_arvalid <= 0;
            while (!s_rv32_rvalid) @(posedge clk);
            data = s_rv32_rdata;
            @(posedge clk);
            s_rv32_rready <= 0;
            @(posedge clk);
        end
    endtask

    // ARM write task
    task arm_write(input [11:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_arm_awaddr  <= addr;
            s_arm_awprot  <= 3'b000;
            s_arm_awvalid <= 1'b1;
            s_arm_wdata   <= data;
            s_arm_wstrb   <= 4'b1111;
            s_arm_wvalid  <= 1'b1;
            s_arm_bready  <= 1'b1;

            fork
                begin while (!s_arm_awready) @(posedge clk); @(posedge clk); s_arm_awvalid <= 0; end
                begin while (!s_arm_wready)  @(posedge clk); @(posedge clk); s_arm_wvalid  <= 0; end
            join
            while (!s_arm_bvalid) @(posedge clk);
            @(posedge clk);
            s_arm_bready <= 0;
            @(posedge clk);
        end
    endtask

    // ARM read task
    task arm_read(input [11:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            s_arm_araddr  <= addr;
            s_arm_arprot  <= 3'b000;
            s_arm_arvalid <= 1'b1;
            s_arm_rready  <= 1'b1;
            while (!s_arm_arready) @(posedge clk);
            @(posedge clk);
            s_arm_arvalid <= 0;
            while (!s_arm_rvalid) @(posedge clk);
            data = s_arm_rdata;
            @(posedge clk);
            s_arm_rready <= 0;
            @(posedge clk);
        end
    endtask

    reg [31:0] rdata;
    integer errors = 0;

    initial begin
        clk = 0;
        rst_n = 0;
        s_arm_awaddr = 0; s_arm_awprot = 0; s_arm_awvalid = 0; s_arm_wdata = 0; s_arm_wstrb = 0; s_arm_wvalid = 0; s_arm_bready = 0;
        s_arm_araddr = 0; s_arm_arprot = 0; s_arm_arvalid = 0; s_arm_rready = 0;
        s_rv32_awaddr = 0; s_rv32_awprot = 0; s_rv32_awvalid = 0; s_rv32_wdata = 0; s_rv32_wstrb = 0; s_rv32_wvalid = 0; s_rv32_bready = 0;
        s_rv32_araddr = 0; s_rv32_arprot = 0; s_rv32_arvalid = 0; s_rv32_rready = 0;

        #20;
        @(posedge clk);
        rst_n = 1;
        #20;

        $display("=== TEST 1: Check Signature from both ARM and RV32 ports ===");
        arm_read(12'h018, rdata);
        if (rdata !== 32'h53444D42) begin $display("[FAIL] ARM port signature"); errors = errors + 1; end
        else $display("[PASS] ARM port sees signature 0x%08X", rdata);

        rv32_read(12'h018, rdata);
        if (rdata !== 32'h53444D42) begin $display("[FAIL] RV32 port signature"); errors = errors + 1; end
        else $display("[PASS] RV32 port sees signature 0x%08X", rdata);

        $display("=== TEST 2: RV32 Issues Request, ARM Serves It ===");
        // RV32 writes LBA 4096, CMD 1 (READ), CONTROL 3 (REQ | IRQ_ARM_EN)
        rv32_write(12'h004, 32'd4096);
        rv32_write(12'h000, 32'd1);
        rv32_write(12'h008, 32'd3);

        // Hardware automatically marks STATUS = 1 (BUSY) and asserts irq_arm
        #10;
        if (irq_arm !== 1'b1) begin $display("[FAIL] irq_arm not asserted!"); errors = errors + 1; end
        else $display("[PASS] irq_arm asserted to wake up ARM");

        // ARM reads request parameters
        arm_read(12'h004, rdata);
        if (rdata !== 32'd4096) begin $display("[FAIL] ARM read sector address"); errors = errors + 1; end
        else $display("[PASS] ARM read sector LBA = %0d", rdata);

        arm_read(12'h000, rdata);
        if (rdata !== 32'd1) begin $display("[FAIL] ARM read command"); errors = errors + 1; end
        else $display("[PASS] ARM read command = %0d", rdata);

        // ARM writes sector data into mailbox buffer
        arm_write(12'h020, 32'h12345678); // Word 0
        arm_write(12'h21C, 32'hAA550000); // Word 127

        // ARM marks DONE: STATUS = 2, clears REQ
        arm_write(12'h008, 32'd4); // IRQ_RV32_EN, clear REQ
        arm_write(12'h00C, 32'd2); // STATUS = DONE

        #10;
        if (irq_rv32 !== 1'b1) begin $display("[FAIL] irq_rv32 not asserted!"); errors = errors + 1; end
        else $display("[PASS] irq_rv32 asserted to wake up RV32");

        // RV32 reads STATUS
        rv32_read(12'h00C, rdata);
        if (rdata !== 32'd2) begin $display("[FAIL] RV32 did not see DONE status"); errors = errors + 1; end
        else $display("[PASS] RV32 observed STATUS = DONE (2)");

        // RV32 reads data buffer
        rv32_read(12'h020, rdata);
        if (rdata !== 32'h12345678) begin $display("[FAIL] Word 0 mismatch"); errors = errors + 1; end
        else $display("[PASS] RV32 read Word 0: 0x%08X", rdata);

        rv32_read(12'h21C, rdata);
        if (rdata !== 32'hAA550000) begin $display("[FAIL] Word 127 mismatch"); errors = errors + 1; end
        else $display("[PASS] RV32 read Word 127: 0x%08X", rdata);

        // RV32 sets STATUS back to IDLE
        rv32_write(12'h00C, 32'd0);
        #10;
        if (irq_rv32 !== 1'b0) begin $display("[FAIL] irq_rv32 should be 0"); errors = errors + 1; end
        else $display("[PASS] RV32 cleared status back to IDLE");

        $display("=================================================");
        if (errors == 0) $display(">>> DUAL-PORT MAILBOX SIMULATION PASSED! <<<");
        else $display(">>> FAILED WITH %0d ERRORS <<<", errors);
        $display("=================================================");

        #50;
        $finish;
    end

endmodule

