module decoder(
    input [31:0] instr,

    output reg [6:0] opcodout,
    output reg [4:0] rd,
    output reg [4:0] rs1,
    output reg [4:0] rs2,
    output reg [2:0] func3,
    output reg [6:0] func7,
    output reg [31:0] imm
);

always @(*)
begin
    // Defaults to prevent inferred latches
    opcodout = 7'd0;
    rd       = 5'd0;
    rs1      = 5'd0;
    rs2      = 5'd0;
    func3    = 3'd0;
    func7    = 7'd0;
    imm      = 32'd0;

    // R-FORMAT
    // opcode = 0110011 = 51

    if (instr[6:0] == 7'd51)
    begin
        opcodout = instr[6:0];
        rd       = instr[11:7];
        func3    = instr[14:12];
        rs1      = instr[19:15];
        rs2      = instr[24:20];
        func7    = instr[31:25];
        imm      = 32'd0;
    end



    // I-FORMAT ALU
    // opcode = 0010011 = 19

    else if (instr[6:0] == 7'd19)
    begin
        opcodout = instr[6:0];
        rd       = instr[11:7];
        func3    = instr[14:12];
        rs1      = instr[19:15];
        rs2      = 5'd0;
        func7    = instr[31:25];
        imm      = {{20{instr[31]}}, instr[31:20]};
    end



    // LOAD I-FORMAT
    // opcode = 0000011 = 3

    else if (instr[6:0] == 7'd3)
    begin
        opcodout = instr[6:0];
        rd       = instr[11:7];
        func3    = instr[14:12];
        rs1      = instr[19:15];
        rs2      = 5'd0;
        func7    = 7'd0;
        imm      = {{20{instr[31]}}, instr[31:20]};
    end



    // S-FORMAT
    // opcode = 0100011 = 35

    else if (instr[6:0] == 7'd35)
    begin
        opcodout = instr[6:0];
        rd       = 5'd0;
        func3    = instr[14:12];
        rs1      = instr[19:15];
        rs2      = instr[24:20];
        func7    = instr[31:25];
        imm      = {{20{instr[31]}},
                    instr[31:25],
                    instr[11:7]};
    end



    // B-FORMAT
    // opcode = 1100011 = 99

    else if (instr[6:0] == 7'd99)
    begin
        opcodout = instr[6:0];
        rd       = 5'd0;
        func3    = instr[14:12];
        rs1      = instr[19:15];
        rs2      = instr[24:20];
        func7    = instr[31:25];

        imm = {{19{instr[31]}},
               instr[31],
               instr[7],
               instr[30:25],
               instr[11:8],
               1'b0};
    end



    // LUI U-FORMAT
    // opcode = 0110111 = 55

    else if (instr[6:0] == 7'd55)
    begin
        opcodout = instr[6:0];
        rd       = instr[11:7];
        rs1      = 5'd0;
        rs2      = 5'd0;
        func3    = 3'd0;
        func7    = 7'd0;

        imm = {instr[31:12], 12'd0};
    end



    // AUIPC U-FORMAT
    // opcode = 0010111 = 23

    else if (instr[6:0] == 7'd23)
    begin
        opcodout = instr[6:0];
        rd       = instr[11:7];
        rs1      = 5'd0;
        rs2      = 5'd0;
        func3    = 3'd0;
        func7    = 7'd0;

        imm = {instr[31:12], 12'd0};
    end



    // JAL J-FORMAT
    // opcode = 1101111 = 111

    else if (instr[6:0] == 7'd111)
    begin
        opcodout = instr[6:0];
        rd       = instr[11:7];
        rs1      = 5'd0;
        rs2      = 5'd0;
        func3    = 3'd0;
        func7    = 7'd0;

        imm = {{11{instr[31]}},
               instr[31],
               instr[19:12],
               instr[20],
               instr[30:21],
               1'b0};
    end



    // JALR I-FORMAT
    // opcode = 1100111 = 103

    else if (instr[6:0] == 7'd103)
    begin
        opcodout = instr[6:0];
        rd       = instr[11:7];
        func3    = instr[14:12];
        rs1      = instr[19:15];
        rs2      = 5'd0;
        func7    = 7'd0;

        imm = {{20{instr[31]}}, instr[31:20]};
    end

end

endmodule
