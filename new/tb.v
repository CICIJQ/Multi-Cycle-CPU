`timescale 1ns / 1ps

// cpu_tb.v - 测试平台
module cpu_tb;

    reg clk;
    reg reset;

    // 实例化CPU顶层模块
    cpu_top cpu (
        .clk(clk),
        .reset(reset)
    );

    // 产生时钟：周期10ns
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 每5纳秒翻转时钟信号，产生周期10ns的时钟
    end

    // 仿真初始化：加载指令内存，释放复位
    initial begin
        // 加载指令存储器内容
        // 假设 instr_mem 是 IF 模块中 IM 的内存数组（如 reg [7:0] instr_mem[0:1023]）
        $readmemh("test_program.mem", cpu.IF_stage.IM.instr_mem);

        // 打开波形输出文件（可用 GTKWave 查看）
        $dumpfile("cpu_wave.vcd");
        $dumpvars(0, cpu_tb);

        // 上电复位，保持一段时间后释放
        reset = 1;
        #20;
        reset = 0;
    end

    // 仿真周期计数与终止控制
    integer cycle_count = 0;
    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;

        if (cpu.u_control.Halt == 1) begin
            $display("? CPU halted at cycle %d", cycle_count);
            $display("=== 寄存器值打印 ===");
            $display("x1  = 0x%08X", cpu.u_regfile.regs[1]);
            $display("x2  = 0x%08X", cpu.u_regfile.regs[2]);
            $display("x3  = 0x%08X", cpu.u_regfile.regs[3]);
            $display("x4  = 0x%08X", cpu.u_regfile.regs[4]);
            $display("x5  = 0x%08X", cpu.u_regfile.regs[5]);
            $display("x6  = 0x%08X", cpu.u_regfile.regs[6]);
            $display("x7  = 0x%08X", cpu.u_regfile.regs[7]);
            $display("x8  = 0x%08X", cpu.u_regfile.regs[8]);
            $display("x9  = 0x%08X", cpu.u_regfile.regs[9]);
            $display("x10 = 0x%08X (应为溢出异常Cause=2)", cpu.u_regfile.regs[10]);
            $display("x31 = 0x%08X (保存异常前PC+4)", cpu.u_regfile.regs[31]);

            $display("\n=== 内存值打印 ===");
            $display("Mem[0x400] = 0x%08X (应为 0xFFFF1234)", cpu.u_memory.mem[32'h400 >> 2]);
            $display("CauseReg   = 0x%08X (应为 1 表示非法指令异常)", cpu.u_memory.causeReg);

            $finish;
        end

        // 超时保护
        if (cycle_count > 2000) begin
            $display("Simulation timed out at cycle %d. Halt 未触发。", cycle_count);
            $finish;
        end
    end

endmodule
