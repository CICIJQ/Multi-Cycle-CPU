`timescale 1ns / 1ps
// ControlUnit.v - 控制单元 FSM模块
module ControlUnit(
    input  wire       clk,         // 时钟信号
    input  wire       reset,       // 复位信号
    // 指令输入
    input  wire [6:0] opcode,      // 7位操作码
    input  wire [2:0] funct3,      // 3位功能码
    input  wire       funct7_5,    // funct7的第5位(区分ADD/SUB)
    // ALU状态输入
    input  wire       Zero,        // ALU零标志
    input  wire       Overflow,    // ALU溢出标志
    // 控制信号输出
    output reg        PCWrite,     // PC写使能
    output reg        IRWrite,     // 指令寄存器写使能
    output reg        RegWrite,    // 寄存器写使能
    output reg        MemRead,     // 内存读使能
    output reg        MemWrite,    // 内存写使能
    output reg        MemtoReg,    // 写回数据选择(0=ALU,1=内存)
    output reg [1:0]  ALUSrcA,     // ALU输入A选择
    output reg [1:0]  ALUSrcB,     // ALU输入B选择
    output reg [2:0]  ALUControl,  // ALU操作控制
    // 异常处理
    output reg        CauseWrite,  // 异常原因寄存器写使能
    output reg [31:0] cause_code,  // 异常原因代码
    output reg        Halt,        // 停机信号
    output reg        Trap,        // 异常跳转信号
    output reg        TrapReturn,  // 异常返回信号
    output reg        is_jalr      // JALR指令标识
);
    // 状态编码
    localparam S_IF        = 4'd0;   // 取指
    localparam S_ID        = 4'd1;   // 译码/取寄存器值
    localparam S_EX_ALU    = 4'd2;   // ALU执行阶段（算术/逻辑或地址计算）
    localparam S_EX_MEM    = 4'd3;   // 地址计算阶段
    localparam S_EX_BRANCH = 4'd4;   // 分支判断
    localparam S_EX_JAL    = 4'd5;   // 跳转计算 (JAL/JALR)
    localparam S_WB_ALU    = 4'd6;   // 算术/逻辑ALU结果写回
    localparam S_MEM_READ  = 4'd7;   // 内存读
    localparam S_MEM_WRITE = 4'd8;   // 内存写
    localparam S_WB_MEM    = 4'd9;   // 内存读结果写回
    localparam S_ILLEGAL   = 4'd10;  // 非法指令异常处理
    localparam S_OVERFLOW  = 4'd11;  // 算术溢出异常处理
    localparam S_HALTED    = 4'd12;  // 停机状态
    localparam S_TRAP_WB   = 4'd13;  // 异常返回地址写回 (写x31)
    localparam S_BRANCH_TAKE = 4'd14; // 分支跳转地址计算
    
    reg [3:0] state, next_state;
    
    // 状态机输出组合逻辑
    always @(*) begin
        // 默认情况下关闭所有控制信号
        PCWrite    = 1'b0;
        IRWrite    = 1'b0;
        RegWrite   = 1'b0;
        MemRead    = 1'b0;
        MemWrite   = 1'b0;
        MemtoReg   = 1'b0;
        ALUSrcA    = 2'b01;
        ALUSrcB    = 2'b00;
        ALUControl = 3'b000;
        CauseWrite = 1'b0;
        cause_code = 32'b0;
        Halt       = 1'b0;
        Trap       = 1'b0;
        TrapReturn = 1'b0;
        is_jalr    = 1'b0;
        next_state = state;
        
        case (state)
            S_IF: begin
                // 取指：Memory读取指令，ALU计算PC+4
                MemRead    = 1'b1;
                IRWrite    = 1'b1;
                ALUSrcA    = 2'b00;    // A = PC
                ALUSrcB    = 2'b10;    // B = 4
                ALUControl = 3'b000;   // 执行ADD计算PC+4
                PCWrite    = 1'b1;     // 更新PC为PC+4
                next_state = S_ID;
            end
            S_ID: begin
                // ECALL识别
                if (opcode == 7'b1110011 && funct3 == 3'b000) begin
                    // 识别 ECALL (0x73)，进入停机
                    next_state = S_HALTED;
                end
                // 译码，根据指令opcode决定后续路径
                else if (opcode == 7'b0110011) begin
                    // R型指令 (ADD/SUB/OR)
                    if ((funct3 == 3'b000 && (funct7_5 == 1'b0 || funct7_5 == 1'b1)) ||
                        (funct3 == 3'b110 && funct7_5 == 1'b0)) begin
                        // 合法R型: ADD, SUB, OR
                        next_state = S_EX_ALU;
                    end else begin
                        // 其他R型指令视为非法
                        next_state = S_ILLEGAL;
                    end
                end else if (opcode == 7'b0010011 && funct3 == 3'b000) begin
                    // I型指令: ADDI
                    next_state = S_EX_ALU;
                end else if (opcode == 7'b0000011 && funct3 == 3'b010) begin
                    // I型指令: LW
                    next_state = S_EX_ALU;
                end else if (opcode == 7'b0100011 && funct3 == 3'b010) begin
                    // S型指令: SW
                    next_state = S_EX_ALU;
                end else if (opcode == 7'b0110111) begin
                    // U型指令: LUI
                    next_state = S_EX_ALU;
                end else if (opcode == 7'b1100011 && funct3 == 3'b000) begin
                    // B型指令: BEQ
                    next_state = S_EX_BRANCH;
                end else if (opcode == 7'b1101111) begin
                    // J型指令: JAL
                    next_state = S_EX_JAL;
                end else if (opcode == 7'b1100111 && funct3 == 3'b000) begin
                    // JALR指令
                    next_state = S_EX_JAL;
                end else begin
                    // 未知指令，触发非法指令异常
                    next_state = S_ILLEGAL;
                end
            end
            S_EX_ALU: begin
                // 执行算术/逻辑或地址计算
                if (opcode == 7'b0110111) begin
                    // LUI：ALU执行 0 + imm
                    ALUSrcA    = 2'b10;    // A = 0
                    ALUSrcB    = 2'b01;    // B = imm
                    ALUControl = 3'b000;   // ADD
                end else if (opcode == 7'b0010011 && funct3 == 3'b000) begin
                    // ADDI：ALU执行 A + imm
                    ALUSrcA    = 2'b01;    // A = rs1值
                    ALUSrcB    = 2'b01;    // B = imm
                    ALUControl = 3'b000;   // ADD
                end else if (opcode == 7'b0110011) begin
                    // R型 (ADD/SUB/OR) 运算
                    ALUSrcA = 2'b01;       // A = rs1
                    ALUSrcB = 2'b00;       // B = rs2
                    case (funct3)
                        3'b000: ALUControl = (funct7_5 == 1'b1) ? 3'b001 : 3'b000; // SUB : ADD
                        3'b110: ALUControl = 3'b010; // OR
                        default: ALUControl = 3'b000;//ADD
                    endcase
                end else if ((opcode == 7'b0000011 && funct3 == 3'b010) ||
                             (opcode == 7'b0100011 && funct3 == 3'b010)) begin
                    // LW/SW地址计算: ALU执行 rs1 + imm
                    ALUSrcA    = 2'b01;    // A = 基址rs1
                    ALUSrcB    = 2'b01;    // B = 偏移imm
                    ALUControl = 3'b000;   // ADD
                end
                // 检查运算溢出
                if (Overflow) begin
                    // 算术溢出，进入异常处理
                    next_state = S_OVERFLOW;
                end else begin
                    // 根据指令类型决定下一状态
                    if (opcode == 7'b0110011 || opcode == 7'b0010011 || opcode == 7'b0110111) begin
                        // 算术/逻辑运算完成，进入写回阶段
                        next_state = S_WB_ALU;
                    end else if (opcode == 7'b0000011) begin
                        // LW地址计算完成，进入内存读阶段
                        next_state = S_MEM_READ;
                    end else if (opcode == 7'b0100011) begin
                        // SW地址计算完成，进入内存写阶段
                        next_state = S_MEM_WRITE;
                    end else begin
                        next_state = S_ID;
                    end
                end
            end
            S_EX_BRANCH: begin
                // 分支判断（BEQ）
                // 先用ALU执行 A - B
                ALUSrcA    = 2'b01;
                ALUSrcB    = 2'b00;
                ALUControl = 3'b001;   // SUB用于比较
                // 判断Zero标志决定是否跳转
                if (Zero) 
                    next_state = S_BRANCH_TAKE;
                else
                    next_state = S_IF;  // 返回取指阶段
            end
            S_BRANCH_TAKE: begin
                ALUSrcA    = 2'b11;  // A = OldPC（当前分支指令地址）
                ALUSrcB    = 2'b01;  // B = 分支偏移imm
                ALUControl = 3'b000; // 计算跳转目标地址
                PCWrite    = 1'b1;                    
                next_state = S_IF;   // 返回取指阶段
            end
            S_EX_JAL: begin
                // 无条件跳转计算（JAL/JALR）
                if (opcode == 7'b1100111) begin
                    // JALR: 目标地址 = x[rs1] + imm
                    ALUSrcA    = 2'b01;  // A = rs1值
                    ALUSrcB    = 2'b01;  // B = imm
                end else begin
                    // JAL: 目标地址 = OldPC + imm
                    ALUSrcA    = 2'b11;  // A = OldPC（当前指令地址）
                    ALUSrcB    = 2'b01;  // B = imm
                end
                ALUControl = 3'b000;
                PCWrite    = 1'b1;   // 更新PC为计算出的目标地址
                // 链接地址（返回地址）= OldPC + 4 已经在IF阶段更新后存于PC
                // 在随后WB阶段将该返回地址写入目标寄存器rd
                next_state = S_WB_ALU;
            end
            S_WB_ALU: begin
                // 算术/逻辑运算结果或JAL跳转返回地址写回寄存器
                RegWrite  = 1'b1;
                MemtoReg  = 1'b0;   // 从ALUOut获取写回数据
                next_state = S_IF;
            end
            S_MEM_READ: begin
                // 内存读（LW）：启动存储器读，结果下个周期进入MDR
                MemRead   = 1'b1;
                next_state = S_WB_MEM;
            end
            S_MEM_WRITE: begin
                // 内存写（SW）：写存储器数据
                MemWrite  = 1'b1;
                next_state = S_IF;
            end
            S_WB_MEM: begin
                // 内存读结果写回寄存器（LW）
                RegWrite  = 1'b1;
                MemtoReg  = 1'b1;   // 从MDR获取写回数据
                next_state = S_IF;
            end
            S_ILLEGAL: begin
                // 非法指令异常处理
                CauseWrite = 1'b1;
                cause_code = 32'h1;      // 异常原因: 非法指令
                // 计算返回地址 PC+4 = OldPC + 4，并暂存到ALUOut
                ALUSrcA    = 2'b11;
                ALUSrcB    = 2'b10;
                ALUControl = 3'b000;
                // 发出异常跳转信号（PC 将在时序电路中置为0x300）
                Trap       = 1'b1;
                next_state = S_TRAP_WB;
            end
            S_OVERFLOW: begin
                // 算术溢出异常处理
                CauseWrite = 1'b1;
                cause_code = 32'h2;      // 异常原因: 算术溢出
                // 计算返回地址 PC+4 = OldPC + 4
                ALUSrcA    = 2'b11;
                ALUSrcB    = 2'b10;
                ALUControl = 3'b000;
                Trap       = 1'b1;
                next_state = S_TRAP_WB;
            end
            S_TRAP_WB: begin
                // 异常返回地址写回阶段：将 PC+4 写入 x31
                RegWrite   = 1'b1;
                MemtoReg   = 1'b0;    // 返回地址保存在ALUOut
                TrapReturn = 1'b1;    // 指示目标寄存器为x31
                next_state = S_IF;    // 转去取指异常处理程序的第一条指令
            end
            S_HALTED: begin
                // 停机状态：CPU保持停止
                Halt       = 1'b1;
                next_state = S_HALTED;
            end
        endcase
    end
    
    // 状态寄存器时序逻辑
    always @(posedge clk or posedge reset) begin
        if (reset)
            state <= S_IF;  // 复位时回到初始状态
        else
            state <= next_state;  // 正常状态转移
    end
endmodule
