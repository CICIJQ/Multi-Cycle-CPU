`timescale 1ns / 1ps

// ALU.v - 算术逻辑单元模块
module ALU(
    input  wire [31:0] A,          // 32位输入A
    input  wire [31:0] B,          // 32位输入B
    input  wire [2:0]  ALUControl, // 3位ALU控制信号
    output reg  [31:0] Result,     // 32位运算结果
    output reg         Zero,       // 零标志(结果为0时为1)
    output reg         Overflow    // 溢出标志
);
    reg signed [31:0] As;
    reg signed [31:0] Bs;
    always @(*) begin
        As = A;
        Bs = B;
        Overflow = 1'b0;
        case (ALUControl)
            3'b000: begin // ADD
                Result = A + B;
                // 检测符号溢出：A和B同号且结果与A符号不同
                if ((A[31] == B[31]) && (Result[31] != A[31]))
                    Overflow = 1'b1;
            end
            3'b001: begin // SUB
                Result = A - B;
                // 检测符号溢出：A和B符号不同且结果符号与A符号不同
                if ((A[31] != B[31]) && (Result[31] != A[31]))
                    Overflow = 1'b1;
            end
            3'b010: begin // OR
                Result = A | B;
                Overflow = 1'b0;
            end
            default: begin
                Result = 32'b0;
                Overflow = 1'b0;
            end
        endcase
        Zero = (Result == 32'b0);
    end
endmodule 