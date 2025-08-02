`timescale 1ns / 1ps

// cpu_tb.v - ����ƽ̨
module cpu_tb;

    reg clk;
    reg reset;

    // ʵ����CPU����ģ��
    cpu_top cpu (
        .clk(clk),
        .reset(reset)
    );

    // ����ʱ�ӣ�����10ns
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // ÿ5���뷭תʱ���źţ���������10ns��ʱ��
    end

    // �����ʼ��������ָ���ڴ棬�ͷŸ�λ
    initial begin
        // ����ָ��洢������
        // ���� instr_mem �� IF ģ���� IM ���ڴ����飨�� reg [7:0] instr_mem[0:1023]��
        $readmemh("test_program.mem", cpu.IF_stage.IM.instr_mem);

        // �򿪲�������ļ������� GTKWave �鿴��
        $dumpfile("cpu_wave.vcd");
        $dumpvars(0, cpu_tb);

        // �ϵ縴λ������һ��ʱ����ͷ�
        reset = 1;
        #20;
        reset = 0;
    end

    // �������ڼ�������ֹ����
    integer cycle_count = 0;
    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;

        if (cpu.u_control.Halt == 1) begin
            $display("? CPU halted at cycle %d", cycle_count);
            $display("=== �Ĵ���ֵ��ӡ ===");
            $display("x1  = 0x%08X", cpu.u_regfile.regs[1]);
            $display("x2  = 0x%08X", cpu.u_regfile.regs[2]);
            $display("x3  = 0x%08X", cpu.u_regfile.regs[3]);
            $display("x4  = 0x%08X", cpu.u_regfile.regs[4]);
            $display("x5  = 0x%08X", cpu.u_regfile.regs[5]);
            $display("x6  = 0x%08X", cpu.u_regfile.regs[6]);
            $display("x7  = 0x%08X", cpu.u_regfile.regs[7]);
            $display("x8  = 0x%08X", cpu.u_regfile.regs[8]);
            $display("x9  = 0x%08X", cpu.u_regfile.regs[9]);
            $display("x10 = 0x%08X (ӦΪ����쳣Cause=2)", cpu.u_regfile.regs[10]);
            $display("x31 = 0x%08X (�����쳣ǰPC+4)", cpu.u_regfile.regs[31]);

            $display("\n=== �ڴ�ֵ��ӡ ===");
            $display("Mem[0x400] = 0x%08X (ӦΪ 0xFFFF1234)", cpu.u_memory.mem[32'h400 >> 2]);
            $display("CauseReg   = 0x%08X (ӦΪ 1 ��ʾ�Ƿ�ָ���쳣)", cpu.u_memory.causeReg);

            $finish;
        end

        // ��ʱ����
        if (cycle_count > 2000) begin
            $display("Simulation timed out at cycle %d. Halt δ������", cycle_count);
            $finish;
        end
    end

endmodule
