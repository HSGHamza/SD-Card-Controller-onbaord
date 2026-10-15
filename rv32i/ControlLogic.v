module ControlLogic (
    input      [6:0] opcode,
    
    // Control outputs
    output reg       reg_write,   // 1: Write to RegFile (write_enable)
    output reg       mem_read,    // 1: Read from dataMemory (load)
    output reg       mem_write,   // 1: Write to dataMemory (write)
    output reg       alu_src,     // 0: operand 2 is rs2, 1: operand 2 is immediate
    output reg [1:0] mem_to_reg,  // 00: ALU result, 01: Data Memory, 10: PC + 4, 11: Imm
    output reg       branch,      // 1: Branch instruction
    output reg       jump,        // 1: Unconditional Jump (JAL / JALR)
    output reg [1:0] alu_op       // 00: ADD (load/store/auipc), 01: Branch, 10: R/I-type, 11: LUI
);

    // RISC-V 32I Opcodes (decimal matching decoder.v)
    localparam OPCODE_R_TYPE = 7'd51;  // 7'b0110011: ADD, SUB, SLT, etc.
    localparam OPCODE_I_TYPE = 7'd19;  // 7'b0010011: ADDI, SLTI, etc.
    localparam OPCODE_LOAD   = 7'd3;   // 7'b0000011: LW, LB, LH, etc.
    localparam OPCODE_STORE  = 7'd35;  // 7'b0100011: SW, SB, SH
    localparam OPCODE_BRANCH = 7'd99;  // 7'b1100011: BEQ, BNE, BLT, BGE, etc.
    localparam OPCODE_LUI    = 7'd55;  // 7'b0110111: LUI
    localparam OPCODE_AUIPC  = 7'd23;  // 7'b0010111: AUIPC
    localparam OPCODE_JAL    = 7'd111; // 7'b1101111: JAL
    localparam OPCODE_JALR   = 7'd103; // 7'b1100111: JALR

    always @(*) begin
        // Safe default assignments to avoid unwanted latches
        reg_write  = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        alu_src    = 1'b0;
        mem_to_reg = 2'b00;
        branch     = 1'b0;
        jump       = 1'b0;
        alu_op     = 2'b00;

        case (opcode)
            OPCODE_R_TYPE: begin
                reg_write  = 1'b1;
                alu_src    = 1'b0;      // op2 is rs2
                mem_to_reg = 2'b00;     // write ALU result to rd
                alu_op     = 2'b10;     // R-type ALU operation
            end

            OPCODE_I_TYPE: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;      // op2 is immediate
                mem_to_reg = 2'b00;     // write ALU result to rd
                alu_op     = 2'b10;     // I-type ALU operation
            end

            OPCODE_LOAD: begin
                reg_write  = 1'b1;
                mem_read   = 1'b1;      // enable dataMemory read
                alu_src    = 1'b1;      // address = rs1 + imm
                mem_to_reg = 2'b01;     // write memory data to rd
                alu_op     = 2'b00;     // addition for address
            end

            OPCODE_STORE: begin
                mem_write  = 1'b1;      // enable dataMemory write
                alu_src    = 1'b1;      // address = rs1 + imm
                alu_op     = 2'b00;     // addition for address
            end

            OPCODE_BRANCH: begin
                branch     = 1'b1;
                alu_src    = 1'b0;      // compare rs1 and rs2
                alu_op     = 2'b01;     // branch comparison
            end

            OPCODE_LUI: begin
                reg_write  = 1'b1;
                mem_to_reg = 2'b11;     // write immediate directly to rd
                alu_op     = 2'b11;
            end

            OPCODE_AUIPC: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;      // PC + imm
                mem_to_reg = 2'b00;     // write result to rd
                alu_op     = 2'b00;     // addition
            end

            OPCODE_JAL: begin
                reg_write  = 1'b1;
                jump       = 1'b1;
                mem_to_reg = 2'b10;     // write return address (PC + 4) to rd
            end

            OPCODE_JALR: begin
                reg_write  = 1'b1;
                jump       = 1'b1;
                alu_src    = 1'b1;      // target = rs1 + imm
                mem_to_reg = 2'b10;     // write return address (PC + 4) to rd
                alu_op     = 2'b00;     // addition for target
            end

            default: begin
                reg_write  = 1'b0;
                mem_read   = 1'b0;
                mem_write  = 1'b0;
                alu_src    = 1'b0;
                mem_to_reg = 2'b00;
                branch     = 1'b0;
                jump       = 1'b0;
                alu_op     = 2'b00;
            end
        endcase
    end

endmodule
