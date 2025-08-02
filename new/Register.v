`timescale 1ns / 1ps
// RegisterFile.v - �Ĵ�����ģ�� (32 x 32-bit)
module RegisterFile(
    input  wire        clk,       // ʱ���ź�
    input  wire        we,        // дʹ��
    input  wire [4:0]  raddr1,    // ����ַ1
    input  wire [4:0]  raddr2,    // ����ַ2
    input  wire [4:0]  waddr,     // д��ַ
    input  wire [31:0] wdata,     // д����
    output wire [31:0] rdata1,    // ���������1
    output wire [31:0] rdata2     // ���������2
);
    reg [31:0] regs [0:31];       // 32��32λ�Ĵ���
    integer j;
    initial begin
        // ��ʼ�����мĴ���Ϊ0
        for(j = 0; j < 32; j = j + 1)
            regs[j] = 32'b0;
    end
    // д������ʱ��ͬ����
    always @(posedge clk) begin
        if (we && waddr != 5'd0) begin  // дʹ����Ŀ�겻��x0
            regs[waddr] <= wdata;
        end
    end
    // ������������߼�����x0��Ϊ0
    assign rdata1 = (raddr1 == 5'd0) ? 32'b0 : regs[raddr1];
    assign rdata2 = (raddr2 == 5'd0) ? 32'b0 : regs[raddr2];
endmodule


