module instructionMemory (
    input             clk,
    input             reset,
    input      [31:0] address,
    output reg [31:0] data_out
);

    reg [7:0] memory [0:255];

    // Temporary 32-bit buffer to read the file (64 instructions)
    reg [31:0] temp_mem [0:63];
    integer k;

    initial begin
        // 1. Read 32-bit hex instructions from file
        $readmemh("instructions.hex", temp_mem);

        // 2. Unpack the instr into our instr mem
        for (k = 0; k < 64; k = k + 1) begin
            memory[4*k + 0] = temp_mem[k][7:0];   // Byte 0 (LSB)
            memory[4*k + 1] = temp_mem[k][15:8];  // Byte 1
            memory[4*k + 2] = temp_mem[k][23:16]; // Byte 2
            memory[4*k + 3] = temp_mem[k][31:24]; // Byte 3 (MSB)
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            data_out <= 32'b0;
        end else begin
            data_out <= {
                memory[address + 3],
                memory[address + 2],
                memory[address + 1],
                memory[address]
            };
        end
    end

endmodule
