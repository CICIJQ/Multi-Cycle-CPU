`timescale 1ns / 1ps
// cpu_top.v - ����ģ��
module cpu_top(
    input  wire clk,
    input  wire reset
);
    // �ڲ��Ĵ�������������
    reg [31:0] PC;       // ���������(Program Counter)
    reg [31:0] OldPC;    // ����ɵ�PCֵ(�����쳣����)
    reg [31:0] IR;       // ָ��Ĵ���(Instruction Register)
    reg [31:0] A;        // �Ĵ����ļ���ȡ�ĵ�һ��������
    reg [31:0] B;        // �Ĵ����ļ���ȡ�ĵڶ���������
    reg [31:0] ALUOut;   // ALU�������Ĵ���
    reg [31:0] MDR;      // �ڴ����ݼĴ���(Memory Data Register)
    reg [31:0] EPC;      // �쳣������ PC+4
    reg [31:0] Cause;    // bit0: ָ��Ƿ���bit1: �������
    
    // ��ָ���ָ��ֶβ�֣����ڿ��Ƶ�Ԫ�����ִ��ָ��
    wire [6:0] opcode = IR[6:0];   // ������
    wire [2:0] funct3 = IR[14:12]; // ������(3λ)
    wire [6:0] funct7 = IR[31:25]; // ������(7λ)
    wire [4:0] rs1    = IR[19:15]; // Դ�Ĵ���1��ַ
    wire [4:0] rs2    = IR[24:20]; // Դ�Ĵ���2��ַ
    wire [4:0] rd     = IR[11:7];  // Ŀ�ļĴ�����ַ
    // ���Ƶ�Ԫ��������ź�
    wire PCWrite;       // PCдʹ��
    wire IRWrite;       // IRдʹ��
    wire RegWrite;      // �Ĵ���дʹ��
    wire MemRead;       // �ڴ��ʹ��
    wire MemWrite;      // �ڴ�дʹ��
    wire [2:0] ALUControl; // ALU��������
    wire [1:0] ALUSrcA;    // ALU����Aѡ��
    wire [1:0] ALUSrcB;    // ALU����Bѡ��
    wire MemtoReg;      // д������ѡ��(�ڴ��ALU���)
    wire Halt;          // ͣ���ź�
    wire [31:0] cause_code; // �쳣ԭ�����
    wire CauseWrite;    // �쳣ԭ��Ĵ���дʹ��
    wire Trap;          // �쳣��ת�ź�
    wire TrapReturn;    // �쳣�����ź�
    wire is_jalr;       // JALRָ���ʶ
    assign is_jalr = (opcode == 7'b1100111); 
    
    // ��������չ������ָ���ʽ����32λ��������
    reg [31:0] imm_ext;
    always @(*) begin
        case (opcode)
            7'b0010011, // I��ָ�� (ADDI)
            7'b0000011, // I��ָ�� (LW)
            7'b1100111: imm_ext = {{20{IR[31]}}, IR[31:20]};  // I��ָ�� (JALR) 12λ�з���������
            7'b0100011: // S��ָ�� (SW)
                imm_ext = {{20{IR[31]}}, IR[31:25], IR[11:7]};  // 12λ�з���������(��5λ+��7λ)
            7'b1100011: // B��ָ�� (BEQ)
                imm_ext = {{19{IR[31]}}, IR[31], IR[7], IR[30:25], IR[11:8], 1'b0};  // 13λ��������������չ�����λ��
            7'b0110111: // U��ָ�� (LUI)
                imm_ext = {IR[31:12], 12'b0};  // 20λ���������ظ�λ
            7'b1101111: // J��ָ�� (JAL)
                imm_ext = {{11{IR[31]}}, IR[31], IR[19:12], IR[20], IR[30:21], 1'b0}; // 21λ������
            default:
                imm_ext = 32'b0;
        endcase
    end
    
    // ʵ�����Ĵ����� (32��32λ�Ĵ���)
    wire [31:0] regfile_rdata1;
    wire [31:0] regfile_rdata2;
    // ����TrapReturn�źž���д�ؼĴ�����ַ���쳣ʱǿ��Ϊx31��
    wire [4:0] waddr_final = TrapReturn ? 5'd31 : rd;
    RegisterFile u_regfile (
        .clk    (clk),
        .we     (RegWrite),
        .raddr1 (rs1),
        .raddr2 (rs2),
        .waddr  (waddr_final),
        .wdata  (MemtoReg ? MDR : ALUOut),  // ����MemtoRegѡ��д������
        .rdata1 (regfile_rdata1),
        .rdata2 (regfile_rdata2)
    );
    
    // ʵ����ALU
    wire [31:0] ALU_in1;
    wire [31:0] ALU_in2;
    wire [31:0] ALU_result;
    wire ALU_zero;
    wire ALU_overflow;
    // ALU����ѡ���·����
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
    
    // ʵ�����洢�� (ͳһ�ڴ�, Cause�Ĵ�����ַ0x800)
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
    
    // ʵ�������Ƶ�Ԫ FSM
    ControlUnit u_control (
        .clk       (clk),
        .reset     (reset),
        .opcode    (opcode),
        .funct3    (funct3),
        .funct7_5  (funct7[5]),  // ��funct7�ĵ�5λ��������ADD/SUB
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
    
    // ʱ���߼���ʱ�������ظ��¸��Ĵ���
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // �첽��λ������PC����ˮ�Ĵ���
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
            // IFȡֵ�׶Σ�ȡָ����浱ǰPC��OldPC
            if (IRWrite) begin
                IR    <= memory_out;
                OldPC <= PC;
            end
            // ����PC�����ȴ����쳣��ת���������PC����/��ת
            if (Trap) begin
                EPC <= PC;           // ����PC
                PC <= 32'h00000300;  // ��ת���쳣������ڵ�ַ 0x300
            end else if (TrapReturn) begin
                PC <= EPC;           // �쳣����
                Cause <= 32'b0;      // ��Cause
            end else if (PCWrite) begin
                if (is_jalr)
                    PC <= ALU_result & ~32'h1;
                else
                    PC <= ALU_result;
            end
            // ID����׶Σ�����Ĵ�����������ݵ�A��B�Ĵ���
            A <= regfile_rdata1;
            B <= regfile_rdata2;
            // EXִ�н׶Σ�����ALU��������ALUOut�Ĵ���
            ALUOut <= ALU_result;
            // MEM�ô�׶Σ����ڴ�����ʱ������ȡ�����ݱ��浽MDR������LWд�أ�
            if (MemRead && !IRWrite) begin
                MDR <= memory_out;
            end
            // Cause�Ĵ����ɿ��Ƶ�Ԫ�����Ƿ�д cause_code
            if (CauseWrite)
                Cause <= cause_code;
        end
    end
endmodule
