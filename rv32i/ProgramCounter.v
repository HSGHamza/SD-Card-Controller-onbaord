module ProgramCounter (
    input             clk,
    input             reset,
    input      [6:0]  opcode,
    input      [31:0] imm,
    input      [31:0] rs1_data,    // From RegFile rs1out (needed for JALR)
    input             jump,        // Branch condition from bAlu / alu (doesB)
    output reg [31:0] pcRegister
);

    always @(posedge clk) begin
        if (reset) begin
            pcRegister <= 32'd0;
        end else begin
            // 1. JAL (opcode = 111): PC-relative unconditional jump
            if (opcode == 7'd111) begin
                pcRegister <= pcRegister + imm;
            end
            // 2. JALR (opcode = 103): Register-indirect unconditional jump
            else if (opcode == 7'd103) begin
                pcRegister <= (rs1_data + imm) & ~32'd1;
            end
            // 3. Branch (opcode = 99): Conditional jump
            else if (opcode == 7'd99 && jump) begin
                pcRegister <= pcRegister + imm;
            end
            // 4. Sequential execution
            else begin
                pcRegister <= pcRegister + 32'd4;
            end
        end
    end

endmodule
