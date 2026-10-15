`timescale 1ns / 1ps

module tb_rv32i_sd_system;

    reg clk;
    reg reset;

    // ARM Interface wires
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

    wire        irq_arm;
    wire        irq_rv32;
    wire [31:0] pc_debug;

    // Instantiate UUT (RV32I Core + SD Mailbox System)
    rv32i_sd_system #(
        .AXI_ADDR_WIDTH(12),
        .AXI_DATA_WIDTH(32)
    ) uut (
        .clk           (clk),
        .reset         (reset),

        // ARM Interface
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

        .irq_arm       (irq_arm),
        .irq_rv32      (irq_rv32),
        .pc_debug      (pc_debug)
    );

    always #5 clk = ~clk;
    always @(posedge clk) begin
        if (!reset)
            $display("T=%0t PC=%0d Instr=%08X x1=%08X x2=%08X x3=%08X x4=%08X x5=%08X addr=%08X rd=%b rdata=%08X rw=%08X",
                     $time, pc_debug, uut.cpu.instruction, uut.cpu.registerFile.x1, uut.cpu.registerFile.x2,
                     uut.cpu.registerFile.x3, uut.cpu.registerFile.x4, uut.cpu.registerFile.x5,
                     uut.mem_addr, uut.mem_read, uut.ext_mem_rdata, uut.cpu.rw);
    end


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

    initial begin
        $display("=== STARTING RV32I CORE + SD CONTROLLER END-TO-END TEST ===");
        clk = 0;
        reset = 1;
        s_arm_awaddr = 0; s_arm_awprot = 0; s_arm_awvalid = 0; s_arm_wdata = 0; s_arm_wstrb = 0; s_arm_wvalid = 0; s_arm_bready = 0;
        s_arm_araddr = 0; s_arm_arprot = 0; s_arm_arvalid = 0; s_arm_rready = 0;

        #20;
        @(posedge clk);
        reset = 0; // Release RV32 core reset!

        $display("[RV32] Core reset released. CPU starts executing instructions...");

        // Wait until RV32 core issues request to Mailbox (irq_arm asserts or STATUS becomes BUSY)
        wait (irq_arm == 1'b1 || uut.mailbox.reg_status == 32'd1);
        $display("[SUCCESS] RV32 core executed store instructions and triggered SD request!");

        // ARM reads the request
        arm_read(12'h004, rdata); // SD_ADDRESS
        $display("[ARM] Detected Sector Address = %0d (expected 100)", rdata);

        arm_read(12'h000, rdata); // SD_COMMAND
        $display("[ARM] Detected Command = %0d (expected 1 for READ)", rdata);

        // ARM simulates writing sector data into SD_DATA buffer (e.g. 0xDEADBEEF)
        #20;
        $display("[ARM] Writing sector data 0xDEADBEEF to Mailbox buffer...");
        arm_write(12'h020, 32'hDEADBEEF); // SD_DATA[0]

        // ARM marks transaction as DONE
        arm_write(12'h00C, 32'd2); // STATUS = 2 (DONE)
        $display("[ARM] Set SD_STATUS = 2 (DONE). RV32 core should exit loop and read data!");

        // Let RV32 execute loop exit and load instruction
        #80;

        $display("[RV32] Final RegFile x5 (loaded data) = 0x%08X (expected 0xDEADBEEF)", uut.cpu.registerFile.x5);
        if (uut.cpu.registerFile.x5 === 32'hDEADBEEF) begin
            $display("=========================================================");
            $display(">>> TEST PASSED: RV32I CORE SUCCESSFULLY READ SD DATA! <<<");
            $display("=========================================================");
        end else begin
            $display("[FAIL] Data in x5 did not match expected 0xDEADBEEF!");
        end

        #50;
        $finish;
    end

endmodule
