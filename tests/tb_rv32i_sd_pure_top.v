`timescale 1ns / 1ps

module tb_rv32i_sd_pure_top;

    reg        sys_clk;
    reg        btn0;

    wire       sd_cs_n;
    wire       sd_mosi;
    reg        sd_miso;
    wire       sd_sclk;
    reg        sd_cd;

    wire [3:0] led;

    // Instantiate 100% Pure Verilog Top Level
    rv32i_sd_pure_top #(
        .CLK_FREQ_HZ(125_000_000)
    ) uut (
        .sys_clk (sys_clk),
        .btn0    (btn0),
        .sd_cs_n (sd_cs_n),
        .sd_mosi (sd_mosi),
        .sd_miso (sd_miso),
        .sd_sclk (sd_sclk),
        .sd_cd   (sd_cd),
        .led     (led)
    );

    // 125 MHz clock (8ns period)
    always #4 sys_clk = ~sys_clk;

    // Simulated SPI MicroSD Card Model
    reg [47:0] cmd_rx;
    integer    bit_idx;
    integer    byte_idx;

    initial begin
        sys_clk = 0;
        btn0    = 1; // Assert reset
        sd_miso = 1'b1;
        sd_cd   = 1'b0;

        #30;
        @(posedge sys_clk);
        btn0 = 0; // Release reset
        $display("[TB] System reset released. 125MHz Clock running...");

        // SD Card SPI Slave Emulation Loop
        forever begin
            // Wait for Chip Select to go LOW
            wait (!sd_cs_n);

            // Shift in 48-bit command on rising edges of sd_sclk
            cmd_rx = 0;
            for (bit_idx = 47; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                @(posedge sd_sclk);
                cmd_rx[bit_idx] = sd_mosi;
            end

            $display("[SD-CARD] Received SPI Command: 0x%012X (CMD%0d, Arg=0x%08X)",
                     cmd_rx, cmd_rx[45:40], cmd_rx[39:8]);

            // If CMD17 (Read Single Block: 0x51...)
            if (cmd_rx[45:40] == 6'd17) begin
                $display("[SD-CARD] Handling CMD17 Read Sector %0d...", cmd_rx[39:8]);

                // Send R1 Response (0x00 = OK)
                repeat (8) @(negedge sd_sclk) sd_miso = 1'b0;

                // Send Data Start Token (0xFE = 8'b1111_1110)
                repeat (10) @(negedge sd_sclk) sd_miso = 1'b1; // Idle wait
                // Token 0xFE
                @(negedge sd_sclk) sd_miso = 1'b1;
                @(negedge sd_sclk) sd_miso = 1'b1;
                @(negedge sd_sclk) sd_miso = 1'b1;
                @(negedge sd_sclk) sd_miso = 1'b1;
                @(negedge sd_sclk) sd_miso = 1'b1;
                @(negedge sd_sclk) sd_miso = 1'b1;
                @(negedge sd_sclk) sd_miso = 1'b1;
                @(negedge sd_sclk) sd_miso = 1'b0;

                // Stream 512 Bytes
                for (byte_idx = 0; byte_idx < 512; byte_idx = byte_idx + 1) begin
                    reg [7:0] byte_val;
                    if (byte_idx == 510) byte_val = 8'h55;       // MBR Boot signature
                    else if (byte_idx == 511) byte_val = 8'hAA;  // MBR Boot signature
                    else byte_val = byte_idx[7:0];

                    for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                        @(negedge sd_sclk);
                        sd_miso = byte_val[bit_idx];
                    end
                end

                // 2-byte CRC
                repeat (16) @(negedge sd_sclk) sd_miso = 1'b1;
                $display("[SD-CARD] Sector stream complete!");
            end
        end
    end

    // Monitor
    initial begin
        wait (led[3] == 1'b1);
        $display("=========================================================");
        $display(">>> TEST PASSED: PURE VERILOG SYSTEM READ SD DATA! <<<");
        $display(">>> LED[3] = 1 (RV32 confirmed MBR 0x55AA signature) <<<");
        $display("=========================================================");
        #50;
        $finish;
    end

    // Timeout safety
    initial begin
        #5_000_000;
        $display("[FAIL] Simulation timed out!");
        $finish;
    end

endmodule

