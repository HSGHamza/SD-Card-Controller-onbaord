module Datapath (
    input             clk,
    input             reset,
    output     [31:0] pcRegister,
    
    // Memory bus interface (for internal RAM & external SD Controller/peripherals)
    output     [31:0] mem_addr,
    output     [31:0] mem_wdata,
    output            mem_write,
    output            mem_read,
    input      [31:0] ext_mem_rdata
);

    // ==========================================
    // Internal Wires
    // ==========================================
    
    // Instruction Fetch
    wire [31:0] instruction;

    // Decoder outputs
    wire [6:0]  opcodout;
    wire [4:0]  rd;
    wire [4:0]  rs1;
    wire [4:0]  rs2;
    wire [2:0]  func3;
    wire [6:0]  func7;
    wire [31:0] imm;

    // Control Unit outputs
    wire        reg_write;
    wire        ctrl_mem_read;
    wire        ctrl_mem_write;
    wire        alu_src;
    wire [1:0]  mem_to_reg;
    wire        branch;
    wire        jump_ctrl;
    wire [1:0]  alu_op;

    // Register File
    wire [31:0] rs1out;
    wire [31:0] rs2out;
    wire [31:0] rw;             // Writeback data committed to rd

    // Execution / ALU
    wire        jump;           // Branch condition outcome from bAlu / alu
    wire [31:0] alu_out;        // Result computed by ALU

    // Data Memory
    wire [31:0] mem_data_out;   // Loaded data from dataMemory

    // ==========================================
    // 1. Program Counter
    // ==========================================
    ProgramCounter pc (
        .clk(clk),
        .reset(reset),
        .opcode(opcodout),
        .imm(imm),
        .rs1_data(rs1out),
        .jump(jump),
        .pcRegister(pcRegister)
    );

    // ==========================================
    // 2. Instruction Memory (Local ROM / TCM)
    // ==========================================
    instructionMemory instr_mem (
        .clk(clk),
        .reset(reset),
        .address(pcRegister),
        .data_out(instruction)
    );

    // ==========================================
    // 3. Instruction Decoder
    // ==========================================
    decoder decoded (
        .instr(instruction),
        .opcodout(opcodout),
        .rd(rd),
        .rs1(rs1),
        .rs2(rs2),
        .func3(func3),
        .func7(func7),
        .imm(imm)
    );

    // ==========================================
    // 4. Control Logic Unit
    // ==========================================
    ControlLogic control_unit (
        .opcode(opcodout),
        .reg_write(reg_write),
        .mem_read(ctrl_mem_read),
        .mem_write(ctrl_mem_write),
        .alu_src(alu_src),
        .mem_to_reg(mem_to_reg),
        .branch(branch),
        .jump(jump_ctrl),
        .alu_op(alu_op)
    );

    // ==========================================
    // 5. Register File
    // ==========================================
    RegFile registerFile (
        .clk(clk),
        .reset(reset),
        .write_enable(reg_write),
        .rd(rd),
        .rs1(rs1),
        .rs2(rs2),
        .rw(rw),
        .rs1out(rs1out),
        .rs2out(rs2out)
    );

    // ==========================================
    // 6. ALU & Branch Unit
    // ==========================================
    alu alu_inst (
        .clk(clk),
        .opcode(opcodout),
        .pc(pcRegister),
        .op1(rs1out),
        .op2(rs2out),
        .imm(imm),
        .func3(func3),
        .func7(func7),
        .doesB(jump),
        .rw(alu_out)
    );

    // ==========================================
    // 7. Data Memory (Internal RAM) & Peripheral Routing
    // ==========================================
    // Addresses >= 0x4000_0000 are mapped to external peripherals (SD controller, Mailbox)
    wire is_peripheral   = (alu_out >= 32'h4000_0000);
    wire local_mem_read  = ctrl_mem_read  && !is_peripheral;
    wire local_mem_write = ctrl_mem_write && !is_peripheral;

    dataMemory data_mem (
        .clk(clk),
        .load(local_mem_read),
        .write(local_mem_write),
        .address(alu_out),       // ALU computes memory address: rs1 + imm
        .data_in(rs2out),        // Store data from rs2
        .data_out(mem_data_out)
    );

    // External Memory bus outputs for peripherals
    assign mem_addr  = alu_out;
    assign mem_wdata = rs2out;
    assign mem_write = ctrl_mem_write && is_peripheral;
    assign mem_read  = ctrl_mem_read  && is_peripheral;

    // Multiplex read data: if reading peripheral, take ext_mem_rdata, otherwise local dataMemory
    wire [31:0] selected_mem_rdata = is_peripheral ? ext_mem_rdata : mem_data_out;

    // ==========================================
    // 8. Write-Back Multiplexer
    // ==========================================
    // mem_to_reg == 2'b01 selects loaded data from Data Memory / Peripherals (LW)
    // Otherwise selects alu_out (R-type, I-type, LUI, AUIPC, JAL, JALR)
    assign rw = (mem_to_reg == 2'b01) ? selected_mem_rdata : alu_out;

endmodule
