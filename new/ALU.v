`timescale 1ns / 1ps

// ALU.v - �����߼���Ԫģ��
module ALU(
    input  wire [31:0] A,          // 32λ����A
    input  wire [31:0] B,          // 32λ����B
    input  wire [2:0]  ALUControl, // 3λALU�����ź�
    output reg  [31:0] Result,     // 32λ������
    output reg         Zero,       // ���־(���Ϊ0ʱΪ1)
    output reg         Overflow    // �����־
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
                // �����������A��Bͬ���ҽ����A���Ų�ͬ
                if ((A[31] == B[31]) && (Result[31] != A[31]))
                    Overflow = 1'b1;
            end
            3'b001: begin // SUB
                Result = A - B;
                // �����������A��B���Ų�ͬ�ҽ��������A���Ų�ͬ
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