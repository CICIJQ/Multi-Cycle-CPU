`timescale 1ns / 1ps
// ControlUnit.v - ���Ƶ�Ԫ FSMģ��
module ControlUnit(
    input  wire       clk,         // ʱ���ź�
    input  wire       reset,       // ��λ�ź�
    // ָ������
    input  wire [6:0] opcode,      // 7λ������
    input  wire [2:0] funct3,      // 3λ������
    input  wire       funct7_5,    // funct7�ĵ�5λ(����ADD/SUB)
    // ALU״̬����
    input  wire       Zero,        // ALU���־
    input  wire       Overflow,    // ALU�����־
    // �����ź����
    output reg        PCWrite,     // PCдʹ��
    output reg        IRWrite,     // ָ��Ĵ���дʹ��
    output reg        RegWrite,    // �Ĵ���дʹ��
    output reg        MemRead,     // �ڴ��ʹ��
    output reg        MemWrite,    // �ڴ�дʹ��
    output reg        MemtoReg,    // д������ѡ��(0=ALU,1=�ڴ�)
    output reg [1:0]  ALUSrcA,     // ALU����Aѡ��
    output reg [1:0]  ALUSrcB,     // ALU����Bѡ��
    output reg [2:0]  ALUControl,  // ALU��������
    // �쳣����
    output reg        CauseWrite,  // �쳣ԭ��Ĵ���дʹ��
    output reg [31:0] cause_code,  // �쳣ԭ�����
    output reg        Halt,        // ͣ���ź�
    output reg        Trap,        // �쳣��ת�ź�
    output reg        TrapReturn,  // �쳣�����ź�
    output reg        is_jalr      // JALRָ���ʶ
);
    // ״̬����
    localparam S_IF        = 4'd0;   // ȡָ
    localparam S_ID        = 4'd1;   // ����/ȡ�Ĵ���ֵ
    localparam S_EX_ALU    = 4'd2;   // ALUִ�н׶Σ�����/�߼����ַ���㣩
    localparam S_EX_MEM    = 4'd3;   // ��ַ����׶�
    localparam S_EX_BRANCH = 4'd4;   // ��֧�ж�
    localparam S_EX_JAL    = 4'd5;   // ��ת���� (JAL/JALR)
    localparam S_WB_ALU    = 4'd6;   // ����/�߼�ALU���д��
    localparam S_MEM_READ  = 4'd7;   // �ڴ��
    localparam S_MEM_WRITE = 4'd8;   // �ڴ�д
    localparam S_WB_MEM    = 4'd9;   // �ڴ�����д��
    localparam S_ILLEGAL   = 4'd10;  // �Ƿ�ָ���쳣����
    localparam S_OVERFLOW  = 4'd11;  // ��������쳣����
    localparam S_HALTED    = 4'd12;  // ͣ��״̬
    localparam S_TRAP_WB   = 4'd13;  // �쳣���ص�ַд�� (дx31)
    localparam S_BRANCH_TAKE = 4'd14; // ��֧��ת��ַ����
    
    reg [3:0] state, next_state;
    
    // ״̬���������߼�
    always @(*) begin
        // Ĭ������¹ر����п����ź�
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
                // ȡָ��Memory��ȡָ�ALU����PC+4
                MemRead    = 1'b1;
                IRWrite    = 1'b1;
                ALUSrcA    = 2'b00;    // A = PC
                ALUSrcB    = 2'b10;    // B = 4
                ALUControl = 3'b000;   // ִ��ADD����PC+4
                PCWrite    = 1'b1;     // ����PCΪPC+4
                next_state = S_ID;
            end
            S_ID: begin
                // ECALLʶ��
                if (opcode == 7'b1110011 && funct3 == 3'b000) begin
                    // ʶ�� ECALL (0x73)������ͣ��
                    next_state = S_HALTED;
                end
                // ���룬����ָ��opcode��������·��
                else if (opcode == 7'b0110011) begin
                    // R��ָ�� (ADD/SUB/OR)
                    if ((funct3 == 3'b000 && (funct7_5 == 1'b0 || funct7_5 == 1'b1)) ||
                        (funct3 == 3'b110 && funct7_5 == 1'b0)) begin
                        // �Ϸ�R��: ADD, SUB, OR
                        next_state = S_EX_ALU;
                    end else begin
                        // ����R��ָ����Ϊ�Ƿ�
                        next_state = S_ILLEGAL;
                    end
                end else if (opcode == 7'b0010011 && funct3 == 3'b000) begin
                    // I��ָ��: ADDI
                    next_state = S_EX_ALU;
                end else if (opcode == 7'b0000011 && funct3 == 3'b010) begin
                    // I��ָ��: LW
                    next_state = S_EX_ALU;
                end else if (opcode == 7'b0100011 && funct3 == 3'b010) begin
                    // S��ָ��: SW
                    next_state = S_EX_ALU;
                end else if (opcode == 7'b0110111) begin
                    // U��ָ��: LUI
                    next_state = S_EX_ALU;
                end else if (opcode == 7'b1100011 && funct3 == 3'b000) begin
                    // B��ָ��: BEQ
                    next_state = S_EX_BRANCH;
                end else if (opcode == 7'b1101111) begin
                    // J��ָ��: JAL
                    next_state = S_EX_JAL;
                end else if (opcode == 7'b1100111 && funct3 == 3'b000) begin
                    // JALRָ��
                    next_state = S_EX_JAL;
                end else begin
                    // δָ֪������Ƿ�ָ���쳣
                    next_state = S_ILLEGAL;
                end
            end
            S_EX_ALU: begin
                // ִ������/�߼����ַ����
                if (opcode == 7'b0110111) begin
                    // LUI��ALUִ�� 0 + imm
                    ALUSrcA    = 2'b10;    // A = 0
                    ALUSrcB    = 2'b01;    // B = imm
                    ALUControl = 3'b000;   // ADD
                end else if (opcode == 7'b0010011 && funct3 == 3'b000) begin
                    // ADDI��ALUִ�� A + imm
                    ALUSrcA    = 2'b01;    // A = rs1ֵ
                    ALUSrcB    = 2'b01;    // B = imm
                    ALUControl = 3'b000;   // ADD
                end else if (opcode == 7'b0110011) begin
                    // R�� (ADD/SUB/OR) ����
                    ALUSrcA = 2'b01;       // A = rs1
                    ALUSrcB = 2'b00;       // B = rs2
                    case (funct3)
                        3'b000: ALUControl = (funct7_5 == 1'b1) ? 3'b001 : 3'b000; // SUB : ADD
                        3'b110: ALUControl = 3'b010; // OR
                        default: ALUControl = 3'b000;//ADD
                    endcase
                end else if ((opcode == 7'b0000011 && funct3 == 3'b010) ||
                             (opcode == 7'b0100011 && funct3 == 3'b010)) begin
                    // LW/SW��ַ����: ALUִ�� rs1 + imm
                    ALUSrcA    = 2'b01;    // A = ��ַrs1
                    ALUSrcB    = 2'b01;    // B = ƫ��imm
                    ALUControl = 3'b000;   // ADD
                end
                // ����������
                if (Overflow) begin
                    // ��������������쳣����
                    next_state = S_OVERFLOW;
                end else begin
                    // ����ָ�����;�����һ״̬
                    if (opcode == 7'b0110011 || opcode == 7'b0010011 || opcode == 7'b0110111) begin
                        // ����/�߼�������ɣ�����д�ؽ׶�
                        next_state = S_WB_ALU;
                    end else if (opcode == 7'b0000011) begin
                        // LW��ַ������ɣ������ڴ���׶�
                        next_state = S_MEM_READ;
                    end else if (opcode == 7'b0100011) begin
                        // SW��ַ������ɣ������ڴ�д�׶�
                        next_state = S_MEM_WRITE;
                    end else begin
                        next_state = S_ID;
                    end
                end
            end
            S_EX_BRANCH: begin
                // ��֧�жϣ�BEQ��
                // ����ALUִ�� A - B
                ALUSrcA    = 2'b01;
                ALUSrcB    = 2'b00;
                ALUControl = 3'b001;   // SUB���ڱȽ�
                // �ж�Zero��־�����Ƿ���ת
                if (Zero) 
                    next_state = S_BRANCH_TAKE;
                else
                    next_state = S_IF;  // ����ȡָ�׶�
            end
            S_BRANCH_TAKE: begin
                ALUSrcA    = 2'b11;  // A = OldPC����ǰ��ָ֧���ַ��
                ALUSrcB    = 2'b01;  // B = ��֧ƫ��imm
                ALUControl = 3'b000; // ������תĿ���ַ
                PCWrite    = 1'b1;                    
                next_state = S_IF;   // ����ȡָ�׶�
            end
            S_EX_JAL: begin
                // ��������ת���㣨JAL/JALR��
                if (opcode == 7'b1100111) begin
                    // JALR: Ŀ���ַ = x[rs1] + imm
                    ALUSrcA    = 2'b01;  // A = rs1ֵ
                    ALUSrcB    = 2'b01;  // B = imm
                end else begin
                    // JAL: Ŀ���ַ = OldPC + imm
                    ALUSrcA    = 2'b11;  // A = OldPC����ǰָ���ַ��
                    ALUSrcB    = 2'b01;  // B = imm
                end
                ALUControl = 3'b000;
                PCWrite    = 1'b1;   // ����PCΪ�������Ŀ���ַ
                // ���ӵ�ַ�����ص�ַ��= OldPC + 4 �Ѿ���IF�׶θ��º����PC
                // �����WB�׶ν��÷��ص�ַд��Ŀ��Ĵ���rd
                next_state = S_WB_ALU;
            end
            S_WB_ALU: begin
                // ����/�߼���������JAL��ת���ص�ַд�ؼĴ���
                RegWrite  = 1'b1;
                MemtoReg  = 1'b0;   // ��ALUOut��ȡд������
                next_state = S_IF;
            end
            S_MEM_READ: begin
                // �ڴ����LW���������洢����������¸����ڽ���MDR
                MemRead   = 1'b1;
                next_state = S_WB_MEM;
            end
            S_MEM_WRITE: begin
                // �ڴ�д��SW����д�洢������
                MemWrite  = 1'b1;
                next_state = S_IF;
            end
            S_WB_MEM: begin
                // �ڴ�����д�ؼĴ�����LW��
                RegWrite  = 1'b1;
                MemtoReg  = 1'b1;   // ��MDR��ȡд������
                next_state = S_IF;
            end
            S_ILLEGAL: begin
                // �Ƿ�ָ���쳣����
                CauseWrite = 1'b1;
                cause_code = 32'h1;      // �쳣ԭ��: �Ƿ�ָ��
                // ���㷵�ص�ַ PC+4 = OldPC + 4�����ݴ浽ALUOut
                ALUSrcA    = 2'b11;
                ALUSrcB    = 2'b10;
                ALUControl = 3'b000;
                // �����쳣��ת�źţ�PC ����ʱ���·����Ϊ0x300��
                Trap       = 1'b1;
                next_state = S_TRAP_WB;
            end
            S_OVERFLOW: begin
                // ��������쳣����
                CauseWrite = 1'b1;
                cause_code = 32'h2;      // �쳣ԭ��: �������
                // ���㷵�ص�ַ PC+4 = OldPC + 4
                ALUSrcA    = 2'b11;
                ALUSrcB    = 2'b10;
                ALUControl = 3'b000;
                Trap       = 1'b1;
                next_state = S_TRAP_WB;
            end
            S_TRAP_WB: begin
                // �쳣���ص�ַд�ؽ׶Σ��� PC+4 д�� x31
                RegWrite   = 1'b1;
                MemtoReg   = 1'b0;    // ���ص�ַ������ALUOut
                TrapReturn = 1'b1;    // ָʾĿ��Ĵ���Ϊx31
                next_state = S_IF;    // תȥȡָ�쳣�������ĵ�һ��ָ��
            end
            S_HALTED: begin
                // ͣ��״̬��CPU����ֹͣ
                Halt       = 1'b1;
                next_state = S_HALTED;
            end
        endcase
    end
    
    // ״̬�Ĵ���ʱ���߼�
    always @(posedge clk or posedge reset) begin
        if (reset)
            state <= S_IF;  // ��λʱ�ص���ʼ״̬
        else
            state <= next_state;  // ����״̬ת��
    end
endmodule
