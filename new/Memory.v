`timescale 1ns / 1ps
// Memory.v - �洢��ģ�� (ͳһ����/���ݴ洢������Cause�Ĵ���ӳ��)
module Memory(
    input  wire        clk,         // ʱ���ź�
    input  wire [31:0] addr,        // 32λ��ַ����
    input  wire [31:0] write_data,  // 32λд������
    input  wire        MemRead,     // �ڴ��ʹ��
    input  wire        MemWrite,    // �ڴ�дʹ��
    output reg  [31:0] read_data,   // 32λ��ȡ����
    input  wire        causeWrite,  // Cause�Ĵ���дʹ��(Ӳ���쳣)
    input  wire [31:0] cause_code   // �쳣ԭ�����
);
    // �ڲ��洢����512��32λ��Ԫ (��ַ0x000~0x7FF, ��2KB)
    reg [31:0] mem [0:511];
    // Cause�Ĵ��� (�洢��ӳ���ַ 0x800)
    reg [31:0] causeReg;
    integer i;
    initial begin
        // ��ʼ���洢����Cause�Ĵ���
        for(i = 0; i < 512; i = i + 1)
            mem[i] = 32'b0;
        causeReg = 32'b0;
        // ���ļ�����ָ��
        $readmemh("test_program.mem", mem);
    mem[12'hC0] = 32'h000F8067; // JALR x0, x31, 0
    end
    // �洢��������������߼���
    always @(*) begin
        if (MemRead) begin
            if (addr == 32'h00000800) begin
                // ����Cause�Ĵ���
                read_data = causeReg;
            end else begin
                // ����һ��洢��Ԫ���ֶ��룩
                read_data = mem[addr[10:2]];
            end
        end else begin
            read_data = 32'b0;
        end
    end
    
    // �洢��д������ʱ���߼���
    always @(posedge clk) begin
        if (causeWrite) begin
            // Ӳ���쳣����: дCause�Ĵ���
            causeReg <= cause_code;
        end else if (MemWrite) begin
            if (addr == 32'h00000800) begin
                // ���д����Cause�Ĵ���
                causeReg <= write_data;
            end else begin
                // дһ��洢��Ԫ
                mem[addr[10:2]] <= write_data;
            end
        end
    end
endmodule
