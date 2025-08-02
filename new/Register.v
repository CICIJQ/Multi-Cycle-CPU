`timescale 1ns / 1ps
// RegisterFile.v - 寄存器堆模块 (32 x 32-bit)
module RegisterFile(
    input  wire        clk,       // 时钟信号
    input  wire        we,        // 写使能
    input  wire [4:0]  raddr1,    // 读地址1
    input  wire [4:0]  raddr2,    // 读地址2
    input  wire [4:0]  waddr,     // 写地址
    input  wire [31:0] wdata,     // 写数据
    output wire [31:0] rdata1,    // 输出读数据1
    output wire [31:0] rdata2     // 输出读数据2
);
    reg [31:0] regs [0:31];       // 32个32位寄存器
    integer j;
    initial begin
        // 初始化所有寄存器为0
        for(j = 0; j < 32; j = j + 1)
            regs[j] = 32'b0;
    end
    // 写操作（时钟同步）
    always @(posedge clk) begin
        if (we && waddr != 5'd0) begin  // 写使能且目标不是x0
            regs[waddr] <= wdata;
        end
    end
    // 读操作（组合逻辑），x0恒为0
    assign rdata1 = (raddr1 == 5'd0) ? 32'b0 : regs[raddr1];
    assign rdata2 = (raddr2 == 5'd0) ? 32'b0 : regs[raddr2];
endmodule


