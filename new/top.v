`timescale 1ns / 1ps
// cpu_top.v - 顶层模块
module cpu_top(
    input  wire clk,
    input  wire reset
);
    // 内部寄存器和连线声明
    reg [31:0] PC;       // 程序计数器(Program Counter)
    reg [31:0] OldPC;    // 保存旧的PC值(用于异常处理)
    reg [31:0] IR;       // 指令寄存器(Instruction Register)
    reg [31:0] A;        // 寄存器文件读取的第一个操作数
    reg [31:0] B;        // 寄存器文件读取的第二个操作数
    reg [31:0] ALUOut;   // ALU计算结果寄存器
    reg [31:0] MDR;      // 内存数据寄存器(Memory Data Register)
    reg [31:0] EPC;      // 异常，保存 PC+4
    reg [31:0] Cause;    // bit0: 指令非法，bit1: 算术溢出
    
    // 将指令字各字段拆分，用于控制单元解码和执行指令
    wire [6:0] opcode = IR[6:0];   // 操作码
    wire [2:0] funct3 = IR[14:12]; // 功能码(3位)
    wire [6:0] funct7 = IR[31:25]; // 功能码(7位)
    wire [4:0] rs1    = IR[19:15]; // 源寄存器1地址
    wire [4:0] rs2    = IR[24:20]; // 源寄存器2地址
    wire [4:0] rd     = IR[11:7];  // 目的寄存器地址
    // 控制单元输出控制信号
    wire PCWrite;       // PC写使能
    wire IRWrite;       // IR写使能
    wire RegWrite;      // 寄存器写使能
    wire MemRead;       // 内存读使能
    wire MemWrite;      // 内存写使能
    wire [2:0] ALUControl; // ALU操作控制
    wire [1:0] ALUSrcA;    // ALU输入A选择
    wire [1:0] ALUSrcB;    // ALU输入B选择
    wire MemtoReg;      // 写回数据选择(内存或ALU结果)
    wire Halt;          // 停机信号
    wire [31:0] cause_code; // 异常原因代码
    wire CauseWrite;    // 异常原因寄存器写使能
    wire Trap;          // 异常跳转信号
    wire TrapReturn;    // 异常返回信号
    wire is_jalr;       // JALR指令标识
    assign is_jalr = (opcode == 7'b1100111); 
    
    // 立即数扩展（根据指令格式生成32位立即数）
    reg [31:0] imm_ext;
    always @(*) begin
        case (opcode)
            7'b0010011, // I型指令 (ADDI)
            7'b0000011, // I型指令 (LW)
            7'b1100111: imm_ext = {{20{IR[31]}}, IR[31:20]};  // I型指令 (JALR) 12位有符号立即数
            7'b0100011: // S型指令 (SW)
                imm_ext = {{20{IR[31]}}, IR[31:25], IR[11:7]};  // 12位有符号立即数(高5位+低7位)
            7'b1100011: // B型指令 (BEQ)
                imm_ext = {{19{IR[31]}}, IR[31], IR[7], IR[30:25], IR[11:8], 1'b0};  // 13位立即数（含零扩展的最低位）
            7'b0110111: // U型指令 (LUI)
                imm_ext = {IR[31:12], 12'b0};  // 20位立即数加载高位
            7'b1101111: // J型指令 (JAL)
                imm_ext = {{11{IR[31]}}, IR[31], IR[19:12], IR[20], IR[30:21], 1'b0}; // 21位立即数
            default:
                imm_ext = 32'b0;
        endcase
    end
    
    // 实例化寄存器堆 (32个32位寄存器)
    wire [31:0] regfile_rdata1;
    wire [31:0] regfile_rdata2;
    // 根据TrapReturn信号决定写回寄存器地址（异常时强制为x31）
    wire [4:0] waddr_final = TrapReturn ? 5'd31 : rd;
    RegisterFile u_regfile (
        .clk    (clk),
        .we     (RegWrite),
        .raddr1 (rs1),
        .raddr2 (rs2),
        .waddr  (waddr_final),
        .wdata  (MemtoReg ? MDR : ALUOut),  // 根据MemtoReg选择写回数据
        .rdata1 (regfile_rdata1),
        .rdata2 (regfile_rdata2)
    );
    
    // 实例化ALU
    wire [31:0] ALU_in1;
    wire [31:0] ALU_in2;
    wire [31:0] ALU_result;
    wire ALU_zero;
    wire ALU_overflow;
    // ALU输入选择多路复用
    assign ALU_in1 = (ALUSrcA == 2'b00) ? PC :
                     (ALUSrcA == 2'b01) ? A :
                     (ALUSrcA == 2'b10) ? 32'b0 :
                                           OldPC;
    assign ALU_in2 = (ALUSrcB == 2'b00) ? B :
                     (ALUSrcB == 2'b01) ? imm_ext :
                     (ALUSrcB == 2'b10) ? 32'd4 :
                                           imm_ext;
    ALU u_alu (
        .A         (ALU_in1),
        .B         (ALU_in2),
        .ALUControl(ALUControl),
        .Result    (ALU_result),
        .Zero      (ALU_zero),
        .Overflow  (ALU_overflow)
    );
    
    // 实例化存储器 (统一内存, Cause寄存器地址0x800)
    wire [31:0] memory_out;
    Memory u_memory (
        .clk       (clk),
        .addr      ((IRWrite) ? PC : ALUOut),
        .write_data(B),
        .MemRead   (MemRead),
        .MemWrite  (MemWrite),
        .read_data (memory_out),
        .causeWrite (CauseWrite),
        .cause_code (cause_code)
    );
    
    // 实例化控制单元 FSM
    ControlUnit u_control (
        .clk       (clk),
        .reset     (reset),
        .opcode    (opcode),
        .funct3    (funct3),
        .funct7_5  (funct7[5]),  // 将funct7的第5位用于区分ADD/SUB
        .Zero      (ALU_zero),
        .Overflow  (ALU_overflow),
        .PCWrite   (PCWrite),
        .IRWrite   (IRWrite),
        .RegWrite  (RegWrite),
        .MemRead   (MemRead),
        .MemWrite  (MemWrite),
        .MemtoReg  (MemtoReg),
        .ALUSrcA   (ALUSrcA),
        .ALUSrcB   (ALUSrcB),
        .ALUControl(ALUControl),
        .CauseWrite(CauseWrite),
        .cause_code(cause_code),
        .Halt      (Halt),
        .Trap       (Trap),
        .TrapReturn (TrapReturn),
        .is_jalr(is_jalr)
    );
    
    // 时序逻辑：时钟上升沿更新各寄存器
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // 异步复位：清零PC及流水寄存器
            PC     <= 32'b0;
            OldPC  <= 32'b0;
            IR     <= 32'b0;
            A      <= 32'b0;
            B      <= 32'b0;
            ALUOut <= 32'b0;
            MDR    <= 32'b0;
            EPC    <= 32'b0;
            Cause  <= 32'b0;
        end else begin
            // IF取值阶段：取指令并保存当前PC到OldPC
            if (IRWrite) begin
                IR    <= memory_out;
                OldPC <= PC;
            end
            // 更新PC：优先处理异常跳转，其次正常PC更新/跳转
            if (Trap) begin
                EPC <= PC;           // 保存PC
                PC <= 32'h00000300;  // 跳转至异常处理入口地址 0x300
            end else if (TrapReturn) begin
                PC <= EPC;           // 异常返回
                Cause <= 32'b0;      // 清Cause
            end else if (PCWrite) begin
                if (is_jalr)
                    PC <= ALU_result & ~32'h1;
                else
                    PC <= ALU_result;
            end
            // ID译码阶段：锁存寄存器堆输出数据到A、B寄存器
            A <= regfile_rdata1;
            B <= regfile_rdata2;
            // EX执行阶段：锁存ALU计算结果到ALUOut寄存器
            ALUOut <= ALU_result;
            // MEM访存阶段：在内存读完成时，将读取的数据保存到MDR（用于LW写回）
            if (MemRead && !IRWrite) begin
                MDR <= memory_out;
            end
            // Cause寄存器由控制单元决定是否写 cause_code
            if (CauseWrite)
                Cause <= cause_code;
        end
    end
endmodule
