`timescale 1ns / 1ps
// Memory.v - 存储器模块 (统一程序/数据存储，包含Cause寄存器映射)
module Memory(
    input  wire        clk,         // 时钟信号
    input  wire [31:0] addr,        // 32位地址输入
    input  wire [31:0] write_data,  // 32位写入数据
    input  wire        MemRead,     // 内存读使能
    input  wire        MemWrite,    // 内存写使能
    output reg  [31:0] read_data,   // 32位读取数据
    input  wire        causeWrite,  // Cause寄存器写使能(硬件异常)
    input  wire [31:0] cause_code   // 异常原因代码
);
    // 内部存储器：512个32位单元 (地址0x000~0x7FF, 共2KB)
    reg [31:0] mem [0:511];
    // Cause寄存器 (存储器映射地址 0x800)
    reg [31:0] causeReg;
    integer i;
    initial begin
        // 初始化存储器和Cause寄存器
        for(i = 0; i < 512; i = i + 1)
            mem[i] = 32'b0;
        causeReg = 32'b0;
        // 从文件加载指令
        $readmemh("test_program.mem", mem);
    mem[12'hC0] = 32'h000F8067; // JALR x0, x31, 0
    end
    // 存储器读操作（组合逻辑）
    always @(*) begin
        if (MemRead) begin
            if (addr == 32'h00000800) begin
                // 访问Cause寄存器
                read_data = causeReg;
            end else begin
                // 访问一般存储单元（字对齐）
                read_data = mem[addr[10:2]];
            end
        end else begin
            read_data = 32'b0;
        end
    end
    
    // 存储器写操作（时序逻辑）
    always @(posedge clk) begin
        if (causeWrite) begin
            // 硬件异常触发: 写Cause寄存器
            causeReg <= cause_code;
        end else if (MemWrite) begin
            if (addr == 32'h00000800) begin
                // 软件写访问Cause寄存器
                causeReg <= write_data;
            end else begin
                // 写一般存储单元
                mem[addr[10:2]] <= write_data;
            end
        end
    end
endmodule
