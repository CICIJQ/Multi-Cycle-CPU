# **计算机组成与体系结构实验报告**

- **实验名称：Lab3 32位 RISC-V 多周期 CPU 设计**



## **一、实验目的**
- 设计并实现一个能够实现指定 RISC-V 指令功能的多周期 CPU 。


## **二、实验要求**
1. 采用多周期组合控制方案，分阶段实现指令执行。
2. 需要完成以下 9 条基本指令：
   加法 add，减法 sub，按位或 or，立即数加法 addi，存储字 sw，加载字 lw，加载高位立即数 lui，分支 beq，跳转并链接 jal。每条指令长度都为 32bits。
3. 编写 Verilog 代码，设计 CPU 的各个部件。其部件资源包括：1）X0-X31共 32 通用寄存器；2）特殊寄存器PC（program counter）。以上寄存器都是 32bits 字长。
4. 存储器采用统一模式， program memory 地址为 0x000 ~ 0x3ff ， data memory 地址为 0x400 ~ 0x7ff （各 1K 字节，采用 little endian 方式存储数据或者指令）。
5. 采用功能仿真逐条验证指令，观察涉及到的寄存器或存储器值的变化。
6. 实现异常服务功能，包括算术溢出和非法指令两种情况 ( Cause 寄存器bit0 = 1（指令非法），bit1 = 1（算术溢出），为 0 表示无异常)。服务程序入口地址为 0x300 ，把 Cause 对应位清 0 即可。


## **三、实验原理**
#### 1. RISC-V 多周期 CPU 是一种基于精简指令集（RISC）架构的处理器。
- 与单周期 CPU 不同，多周期 CPU 将每条指令的执行过程分解为多个步骤，每个步骤在一个时钟周期内完成，从而**一条指令的执行需要多个时钟周期**，**指令的不同阶段共享硬件资源**，硬件资源的利用率高；
- **多周期 CPU 的执行流程**包括：取指（IF）— 译码（ID）— 执行（EX）— 存储（MEM）— 写回（WB）。其中译码阶段包括寄存器读取、立即数扩展，执行阶段包括 ALU 计算、分支计算。

#### 2. 多周期 CPU 的特点：
- **使用有限状态机（FSM）进行控制**，根据指令类型进行状态转移，每个状态负责指令的一个执行阶段，指令执行过程按照状态转移图设计；
- 每个阶段的操作**使用寄存器**（ IR、A、B、ALUOut、MDR 等）**保存中间结果，实现分阶操作**；
- 每个时钟周期内，**所有 reg 型变量只在时钟上升沿更新，赋值一次**，确保数据在同一周期内确定，避免值混乱（不能出现组合逻辑延迟导致寄存器反复赋值的情况）；
- 立即数扩展、 ALU 输入选择等均在组合逻辑完成，一次成型防止在时钟边沿数据不稳定。

#### 3. RISC-V 架构特点：
- RISC-V 有 X0 ~ X31 **共 32 个通用寄存器，X0 的内容恒为 0**；
- 共支持**6 种标准指令格式** ：
  - R 型（寄存器操作指令，如 ADD、SUB、OR）
  - I 型（立即数操作、加载指令，如 ADDI、LW）
  - S 型（存储指令，如 SW）
  - B 型（条件分支，如 BEQ）
  - J 型（无条件跳转，如 JAL）
  - U 型（长立即数加载，如 LUI）

#### 4. 多周期 CPU 的组成：
- **程序计数器 PC** ：32 位，指向当前执行指令的地址，异常时跳转到固定的 0x300 ；
- **通用寄存器堆（ X0 - X31 ）**：32 个 32 位通用寄存器，其中 X0 恒为 0；
- **统一内存模块（Program/Data Memory）**：地址范围 0x000 ~ 0x3FF 存储程序，0x400~0x7FF 存储数据，采取 little endian 方式；
- **特殊寄存器**：
  - IR ：指令寄存器，保存当前指令。
  - EPC ：异常程序计数器，保存异常发生时的 PC + 4。
  - Cause ：异常原因寄存器，低两位分别表示非法指令、算术溢出。
  - OldPC ：保存异常发生时的 PC。
- **数据通路组件**：
  - ALU（算术逻辑单元）：支持加、减、或等基本运算，并提供 Zero 和 Overflow 检测。
  - 寄存器 A、B、ALUOut、MDR：用于暂存数据。

#### 5. 多周期 CPU 的异常处理机制：
- **异常服务入口固定在地址 0x300**；
- 异常发生（如非法指令、溢出）时，CPU 硬件**自动保存 PC+4 到 EPC，并设置 Cause**；
- 服务程序**将 Cause 清零** SW x0, 0(x11) ，然后使用 JALR x0, x31, 0 从 EPC 返回；
- 多周期 CPU 使用**异常跳转信号 Trap、异常返回信号 TrapReturn** 配合状态机控制异常处理流程。


## **四、实验过程（模块设计与实现）**
### 本实验中将 CPU 分为以下模块实现：
  - cpu_top 顶层组合模块
  - ControlUnit 有限状态机控制
  - ALU 算术逻辑单元
  - Memory 组合指令和数据存储器
  - RegisterFile 通用存储器X0-X31
  - EPC/Cause 异常相关特殊存储

### **1. cpu_top 模块**
#### 功能：顶层集成模块，连接多周期 CPU 的各个核心组件，实现整个 CPU 的多周期控制与数据流管理。

#### 输入输出端口：
- 输入：
  - clk：时钟信号
  - reset：复位信号（高电平有效）

#### 实现思路：
- **集成所有部件**：CPU 顶层模块整合了 程序寄存器 PC 、指令寄存器 IR 、通用寄存器堆 X0-X31 、算术逻辑运算单元 ALU 、存储器 Memory 、ALU 结果暂存寄存器 ALUOut 、内存数据寄存器 MDR 、异常原因寄存器 Cause 、异常程序计数器 EPC 、旧程序计数器 OldPC  、操作数 A 寄存器、操作数 B 寄存器 等多周期 CPU 的关键寄存器与运算部件。
  
- **使用组合逻辑与时序逻辑分离**：
  - 各 ALU 输入、立即数扩展等在组合逻辑完成；
  - 所有 reg 型寄存器只在时钟上升沿进行一次赋值，保证数据在一个周期内成型。
  
- **控制信号管理**：接收来自 ControlUnit 的控制信号。（例如：PCWrite、IRWrite、RegWrite、Trap、TrapReturn 等）

- **特殊信号管理**：
  - 异常处理流程中优先处理 Trap，TrapReturn；
  - Cause、EPC 只在特定异常流程中被更新。

#### 与单周期的主要区别：
  - 多周期 CPU 使用寄存器（IR, A, B, ALUOut, MDR）分阶段保存数据；
  - PC 更新、寄存器写入、ALU 运算等分多周期进行，资源复用；
  - 增加了异常处理机制（Trap、TrapReturn），而单周期 CPU 的一条指令在单周期内无法实现此类复杂机制。


### **2. ControlUnit 模块**
#### 功能：多周期控制单元，实现有限状态机（FSM），管理整个 CPU 指令执行的状态转移及相应控制信号生成。

#### 输入输出端口：
- 输入：
  - clk、reset
  - opcode、funct3、funct7_5、ALU_zero、ALU_overflow
- 输出：
  -  各控制信号（PCWrite、IRWrite、RegWrite、MemRead、MemWrite、ALUControl 等）
  -  异常处理相关信号（Trap、TrapReturn、CauseWrite、cause_code）

#### 实现思路：
- 采用 FSM 设计，划分为多个状态（ S_IF, S_ID, S_EX_ALU, S_WB, S_OVERFLOW, S_ILLEGAL 等）；
- 根据当前状态与指令类型、ALU 标志决定下一状态与输出控制信号；
- 异常流程：
  - 在 S_ILLEGAL、S_OVERFLOW 产生 Trap，进入异常服务；
  - 在 S_TRAP_WB 产生 TrapReturn，恢复正常流程。

#### 与单周期的主要区别：
- 单周期 CPU 无状态机，所有信号由组合逻辑直接基于当前指令解码；
- 多周期 CPU 使用 FSM 分时分步控制，允许硬件资源共享；
- 增加了异常状态、异常返回状态，细分处理指令错误、溢出等复杂异常。


### **3. ALU 模块** 
#### 功能：算术逻辑单元，执行 ALU 运算，提供 Zero、Overflow 状态标志。
#### 输入输出端口：
- 输入：
  - A、B：操作数
  - ALUControl：运算类型选择
- 输出：
  - Result：运算结果
  - Zero、Overflow：标志位

#### 实现思路：
- 根据 ALUControl 执行 ADD、SUB、OR 等基本运算；
- 提供溢出检测、零检测。

#### 与单周期的主要区别：
- 多周期 CPU 使用 ALUOut 在 EX 阶段锁存结果，而非组合逻辑直接输出。


### **4. Memory 模块**
#### 功能：统一指令与数据存储模块，支持异常 Cause 映射。

#### 输入输出端口：
- 输入：clk、addr、write_data、MemRead、MemWrite、causeWrite、cause_code
- 输出：read_data

#### 实现思路：
- 统一存储器设计：程序区0x000 ~ 0x3FF，存储指令；数据区：0x400 ~ 0x7FF，存储数据；
- 读操作为组合逻辑，写操作为时序逻辑
- 异常 Cause 寄存器映射访问：
  - 异常 Cause 寄存器映射在地址 0x800，支持 CPU 硬件在异常时写入异常原因；
  - 软件可以通过访问 0x800 地址读取、清除 Cause 寄存器，实现异常服务程序与 CPU 硬件通信。

#### 与单周期的主要区别：
- 单周期 CPU 只执行一周期的读或写，多周期 CPU 将读、写阶段分离为 S_MEM_READ、S_MEM_WRITE ；
- 多周期 CPU 增加 Cause、EPC 支持。


### **5. RegisterFile 模块**
#### 功能：通用寄存器堆（X0-X31）。

#### 输入输出端口：
- 输入：clk、we、waddr、wdata、raddr1、raddr2
- 输出：rdata1、rdata2

#### 实现思路：
- 提供两个读口、一个写口；
- X0 始终为 0，不允许写入。

#### 与单周期的主要区别
- 多周期 CPU 使用 A、B 在 ID 译码阶段锁存寄存器值；
- 写回阶段专用，不能直接在同一周期读写完成。


### **6. EPC、Cause、Trap、TrapReturn 特殊机制**
#### 功能：
- EPC：异常时保存 PC+4，供异常返回使用；
- Cause：记录异常类型，低位分别标识非法指令、溢出；
- Trap：由 ControlUnit 异常状态产生，强制 PC 跳到 0x300；
- TrapReturn：在 S_TRAP_WB 状态产生，PC 返回 EPC。

#### 与单周期的主要区别：
- 单周期 CPU 没有异常机制，执行异常指令直接停机或不可预测；
- 多周期 CPU 使用 Trap、TrapReturn 进行标准异常服务和安全返回。


## **五、实验结果（代码仿真）**
- 注 1 ：由于在 elearning 上传测试程序前已经开始仿真检测，且 elearning 上的代码不含异常处理，因此代码仿真部分使用了自己的测试程序。
- 注 2 ：由于多周期 CPU 的 PC 是组合路径（立即更新），而 IR 是时序寄存器（下一周期才可见）。IRWrite 总是在 MemRead 完成后才被置位，所以 PC 和 IR 会有一个周期的交错。
- PC = 0 时，MemRead 正在读取 0x0 地址，IR 还没写入。此时 PC = 0x00000000，IR = 0x00000000。

#### 1. 指令：LUI x1, 0x1  ( PC = 4 ) 
**机器码**：0x000010B7

**功能**：将 0x1 左移 12 位加载到寄存器 x1 的高20位，低12位置0

**操作**：x1 = 0x1 << 12 = 0x00001000

**中间信号**：
ALUControl：0000（加法）；
ALUOut：0x00001000；
RegWrite：1；waddr = x1，wdata = 0x00001000

- 执行前:
  - x1 = 0x00000000
  - PC = 0x00000000
- 执行后:
  - x1 = 0x00001000
  - PC = 0x00000004
  
<img src="image.png"  width="50%" height="auto">

#### 2. 指令：ADDI x1, x1, 0x234  ( PC = 8 ) 
**机器码**：0x23408093

**功能**：将 x1 加上立即数 0x234，结果写入 x1

**操作**: x1 = x1 + 0x234 = 0x00001000 + 0x00000234 = 0x00001234

**中间信号**：
ALUControl：0000（加法）
ALUOut：0x00001234
RegWrite：1；waddr = x1，wdata = 0x00001234

- 执行前:
  - x1 = 0x00001000
  - PC = 0x00000004
- 执行后:
  - x1 = 0x00001234
  - PC = 0x00000008

<img src="image-1.png"  width="50%" height="auto">

#### 3. 指令：LUI x3, 0xFFFF0  ( PC = 12 ) 
**机器码**：0xFFFF01B7

**功能**：将 0xFFFF0 左移 12 位，写入 x3

**操作**: x3 = 0xFFFF0 << 12 = 0xFFFF0000

**中间信号**：
ALUControl：0001（LUI路径）
ALUOut：0xFFFF0000
RegWrite：1；waddr = x3，wdata = 0xFFFF0000

- 执行前:
  - x3 = 0x00000000
  - PC = 0x00000008
- 执行后:
  - x3 = 0xFFFF0000
  - PC = 0x0000000C

<img src="image-2.png"  width="50%" height="auto">

#### 4. 指令：OR x2, x1, x3  ( PC = 16 ) 
**机器码**：0x0030E133

**功能**：x2 = x1 | x3

**操作**: x2 = 0x00001234 | 0xFFFF0000 = 0xFFFF1234

**中间信号**：
ALUControl：0011（按位或）
ALUOut：0xFFFF1234
RegWrite：1；waddr = x2，wdata = 0xFFFF1234

- 执行前:
  - x1 = 0x00001234
  - x3 = 0xFFFF0000
  - x2 = 0x00000000
  - PC = 0x0000000C
- 执行后:
  - x2 = 0xFFFF1234
  - PC = 0x00000010

<img src="image-3.png"  width="50%" height="auto">

#### 5. 指令：SW x2, 0x400(x0)  ( PC = 20 ) 
**机器码**：0x40202023

**功能**：将 x2 的值存入地址 0x400 (x0 + 0x400)

**操作**: Mem[0x400] = x2 = 0xFFFF1234

**中间信号**：
ALUControl：0000（加法）
ALUOut：0x00000400（目标地址）
MemWrite：1；addr = 0x00000400，write_data = 0xFFFF1234
RegWrite：0

- 执行前:
  - Mem[0x400] = 未定义
  - x2 = 0xFFFF1234
  - PC = 0x00000010
- 执行后:
  - Mem[0x400] = 0xFFFF1234
  - PC = 0x00000014

<img src="image-4.png"  width="50%" height="auto">

#### 6. 指令：LW x4, 0x400(x0)  ( PC = 24 ) 
**机器码**：0x40002203

**功能**：将内存中地址 0x400 的值加载到寄存器 x4

**操作**：x4 = Mem[0x400] = 0xFFFF1234

**中间信号**：
ALUControl：0000（加法）
ALUOut：0x00000400（目标地址）
MemRead：1；addr = 0x00000400，read_data = 0xFFFF1234
RegWrite：1；waddr = x4，wdata = 0xFFFF1234

- 执行前：
  - x4 = 0x00000000
  - PC = 0x00000014
  - Mem[0x400] = 0xFFFF1234
- 执行后：
  - x4 = 0xFFFF1234
  - PC = 0x00000018
  
  <img src="image-5.png"  width="50%" height="auto">

#### 7. 指令：BEQ x2, x4, +8  ( PC = 28 ) 
**机器码**：0x00410463

**功能**：如果 x2 == x4，则跳转 PC + 8

**操作**：x2 = x4 = 0xFFFF1234，跳转成立，PC += 8

**中间信号**：
ALUControl：0001（减法） → Zero = 1
分支跳转判断：满足跳转条件，PC ← PC + 8
PCWriteCond：1（分支有效）
ALUOut：0x00000020
RegWrite：0

- 执行前：
  - x2 = 0xFFFF1234
  - x4 = 0xFFFF1234
  - PC = 0x00000018
- 执行后：
  - PC = 0x00000020

<img src="image-6.png"  width="50%" height="auto">

#### 8. 指令：ADDI x5, x0, 5  ( PC = 32 ) 
**机器码**：0x00500293

**功能**：前面 BEQ 成立，被跳过

#### 9. 指令：BEQ x1, x2, +8  ( PC = 36 ) 
**机器码**：0x00208463

**功能**：如果 x1 == x2，则跳转

**操作**：x1 = 0x00001234 ≠ x2 = 0xFFFF1234，跳转不成立

**中间信号**：
ALUControl：0001（减法） → Zero = 0
分支跳转判断：条件不满足，PC += 4
PCWriteCond：0；PCWrite = 1
ALUOut：跳转目标地址 = 0x0000002C
RegWrite：0

- 执行前：
  - x1 = 0x00001234
  - x2 = 0xFFFF1234
  - PC = 0x00000020
- 执行后：
  - PC = 0x00000024

<img src="image-7.png"  width="50%" height="auto">

#### 10. 指令：ADDI x5, x0, 5  ( PC = 40 ) 
**机器码**：0x00500293

**功能**：将立即数 5 加到寄存器 x0（恒为 0），结果写入 x5

**操作**：x5 = x0 + 0x00000005 = 0x00000005

**中间信号**：
ALUControl：0000（加法）
ALUOut：0x00000005
RegWrite：1；waddr = x5，wdata = 0x00000005

- 执行前：
  - x0 = 0x00000000（恒为 0）
  - x5 = 未定义或前值（上次跳转被跳过）
  - PC = 0x00000024
- 执行后：
  - x5 = 0x00000005
  - PC = 0x00000028

<img src="image-8.png"  width="50%" height="auto">

#### 11. 指令：ADD x5, x1, x0  ( PC = 44 ) 
**机器码**：0x000082B3

**功能**：将 x1 和 x0 相加，写入 x5

**操作**：x5 = x1 + x0 = 0x00001234 + 0 = 0x00001234

**中间信号**：
ALUControl：0000（加法）
ALUOut：0x00001234
RegWrite：1；waddr = x5，wdata = 0x00001234

- 执行前：
  - x1 = 0x00001234
  - x5 = 0x00000005
  - PC = 0x00000028
- 执行后：
  - x5 = 0x00001234
  - PC = 0x0000002C

<img src="image-9.png"  width="50%" height="auto">

#### 12. 非法指令  ( PC = 0x00000300 ) 
**机器码**：0x00000000（不是合法的 RISC-V 指令）

**功能**：触发非法指令异常，Cause[0] ← 1，跳转到异常服务入口 PC = 0x300

**操作**：Cause = 0x00000001（bit0 = 1）；EPC = 0x00000030（当前 PC+4）；PC ← 0x00000300

**中间信号**：
Trap = 1；CauseWrite = 1；cause_code = 0x1（非法指令）
ALUOut：EPC = PC + 4 = 0x00000030
RegWrite：1；waddr = x31，wdata = 0x00000030（EPC写入）

- 执行前：
  - PC = 0x0000002C
- 执行后：
  - Cause = 0x00000001
  - EPC = 0x00000030
  - PC = 0x00000300

<img src="image-10.png"  width="50%" height="auto">


#### 第一处异常：
**类型**：非法指令异常

**异常标识**：控制单元进入S_ILLEGAL 状态，激活异常信号 Trap = 1，通过 CauseWrite = 1 将 Cause[0] 置为 1 表示非法指令。

**操作**：
- ALU 计算 OldPC + 4 = 0x0000002c + 4 = 0x00000030 ，写入通用寄存器 x31（rd = 0x1F），用于后续异常返回
- 仿真波形显示 PCWrite = 1，waddr = 0x1f, wdata = 0x00000030, RegWrite = 1

**异常处理服务程序执行**：（@0x300）
- 清除 Cause 寄存器
  - 指令 sw x0, 0(x11) 执行写入 0x00000000 到地址 0x00000800（Cause 映射地址）
  - 波形中 MemWrite = 1，addr = 0x00000800，write_data = 0x00000000

- 通过 JALR 返回异常前主程序
  - 指令 jalr x0, x31, 0 将 PC ← x31，即 PC = 0x00000030
  - 波形中 PC 成功从 0x304 → 0x30，异常处理完毕


#### 13. 指令：SUB x6, x4, x3  ( PC = 52 ) 
**机器码**：0x40320333

**功能**：x6 = x4 - x3

**操作**：x6 = 0xFFFF1234 - 0xFFFF0000 = 0x00001234

**中间信号**：
ALUControl：0001（减法）
ALUOut：0x00001234
RegWrite：1；waddr = x6，wdata = 0x00001234

- 执行前：
  - x4 = 0xFFFF1234
  - x3 = 0xFFFF0000
  - x6 = 0
  - PC = 0x00000030
- 执行后：
  - x6 = 0x00001234
  - PC = 0x00000034

<img src="image-11.png"  width="50%" height="auto">

#### 14. 指令：JAL x7, +8（PC = 56）
**机器码**：0x008003EF

**功能**：跳转到 PC + 8（即 0x0000030C），并将返回地址 0x00000308 写入 x7

**操作**：x7 = 0x00000308；PC ← 0x0000030C

**中间信号**：
ALUControl：0000（加法）
ALUOut：0x0000003C（跳转地址）
RegWrite：1
waddr = x7
wdata = 0x00000038（= PC + 4）

- 执行前：
  - PC = 0x00000034
- 执行后：
  - x7 = 0x00000308
  - PC = 0x0000003c
  
<img src="image-12.png"  width="50%" height="auto">

#### 15. 指令：ADDI x5, x0, 6（PC = 60）
**机器码**：0x00600293

**功能**：由于前一条指令跳转到 PC + 8 ，本条被跳过

#### 16. 指令：LUI x8, 0x7FFF0（PC = 64）
**机器码**：0x7FFF0437

**功能**：将 0x7FFF0 左移 12 位，写入 x8

**操作**：x8 = 0x7FFF0 << 12 = 0x7FFF0000

**中间信号**：
ALU输入：A = 0，EXT = 0x7FFF0000
ALUControl：0001（LUI路径，直接取EXT）
ALUOut：0x7FFF0000
RegWrite：1；waddr = x8，wdata = 0x7FFF0000

- 执行前：
  - x8 = 0x00000000
  - PC = 0x0000003c
- 执行后：
  - x8 = 0x7FFF0000
  - PC = 0x00000040

<img src="image-13.png"  width="50%" height="auto">

#### 17. 指令：LUI x9, 0x00010（PC = 68）
**机器码**：0x000104B7

**功能**：将立即数 0x00010 左移 12 位后写入 x9 的高位，低 12 位填 0

**操作**：x9 = 0x00010 << 12 = 0x00010000

**中间信号**：
ALU输入：A = 0，EXT = 0x00010000
ALUControl：0001（LUI路径）
ALUOut：0x00010000
RegWrite：1；waddr = x9，wdata = 0x00010000

- 执行前：
  - x9 = 未定义
  - PC = 0x00000040
- 执行后：
  - x9 = 0x00010000
  - PC = 0x00000044

<img src="image-14.png"  width="50%" height="auto">

#### 18. 指令：ADDI x9, x9, -1（PC = 72）
**机器码**：0xFFF48493

**功能**：将立即数 -1 加到 x9 中，结果写回 x9

**操作**：x9 = 0x00010000 - 1 = 0x0000FFFF

**中间信号**：
ALUControl：0000（加法）
ALUOut：0x0000FFFF
RegWrite：1；waddr = x9，wdata = 0x0000FFFF

- 执行前：
  - x9 = 0x00010000
  - PC = 0x00000044
- 执行后：
  - x9 = 0x0000FFFF
  - PC = 0x00000048

<img src="image-15.png"  width="50%" height="auto">

#### 19. 指令：OR x8, x8, x9（PC = 76）
**机器码**：0x00946433

**功能**：将 x8 与 x9 做按位或运算，结果写入 x8

**操作**：x8 = 0x7FFF0000 | 0x0000FFFF = 0x7FFFFFFF

**中间信号**：
ALUControl：0011（OR 运算）
ALUOut：0x7FFFFFFF
RegWrite：1；waddr = x8，wdata = 0x7FFFFFFF
PCWrite：1；PC ← 0x0000004C

- 执行前：
  - x8 = 0x7FFF0000
  - x9 = 0x0000FFFF
  - PC = 0x00000048
- 执行后：
  - x8 = 0x7FFFFFFF
  - PC = 0x0000004c

<img src="image-16.png"  width="50%" height="auto">

#### 20. 指令：ADDI x9, x0, 1（PC = 80）
**机器码**：0x00100493

**功能**：将立即数 1 加到 x0（恒为 0）写入 x9

**操作**：x9 = 0x00000001

**中间信号**：
ALUControl：0000（加法）
ALUOut：0x00000001
RegWrite：1；waddr = x9，wdata = 0x00000001
PCWrite：1；PC ← 0x00000050

- 执行前：
  - x9 = 0x0000FFFF
  - PC = 0x0000004c
- 执行后：
  - x9 = 0x00000001
  - PC = 0x00000050

<img src="image-17.png"  width="50%" height="auto">

#### 21. 指令：ADD x10, x8, x9（PC = 84）
**机器码**：0x00940533

**功能**：将 x8 与 x9 相加，结果写入 x10。此处产生有符号整型溢出。

**操作**：x10 = 0x7FFFFFFF + 1 = 0x80000000（触发溢出）

**异常处理**：Cause[1] 被置位，PC ← 0x00000300

**中间信号**：
Overflow 检测：A>0, B>0, result<0 → 有符号整型溢出（最高位变符号位）
Trap：1；CauseWrite = 1；cause_code = 0x2（bit1 = 1 表示溢出）
RegWrite：1；waddr = x31（x31保存 EPC），wdata = 0x00000054（PC + 4）


- 执行前：
  - x8 = 0x7FFFFFFF
  - x9 = 0x00000001
  - PC = 0x00000050

- 执行后：
  - x10 = 0x80000000
  - Cause = 0x00000002
  - PC = 0x00000300

<img src="image-18.png"  width="50%" height="auto">


#### 第二处异常：
**类型**：算术溢出异常

**异常触发指令**：ADD x10, x8, x9（机器码：0x00940533）

**执行操作**：x8 = 0x7FFFFFFF（最大正整数）；x9 = 0x00000001
- 结果应为 0x80000000，但因为超出 32 位有符号数正数范围（最高位变为符号位），触发溢出
- ALU 溢出标志 Overflow = 1，控制单元进入 S_OVERFLOW 状态

**异常标识**：控制单元将 Trap = 1、CauseWrite = 1 置位；将 cause_code = 0x00000002 写入 Cause 寄存器表示算术溢出

**操作**：
- ALU 同时计算异常返回地址 PC+4 = 0x00000054，写入 x31 寄存器，用于异常返回
- 仿真波形显示 RegWrite = 1，waddr = 0x1F（x31），wdata = 0x00000054（异常返回地址），ALUOut = 0x00000054，PC = 0x00000050 → 0x00000300

**异常处理服务程序执行**：（@0x300）
- 清除 Cause 寄存器
  - 指令 sw x0, 0(x11) 执行写入 0x00000000 到地址 0x00000800（Cause 映射地址）
  - 波形中 MemWrite = 1，addr = 0x00000800，write_data = 0x00000000

- 通过 JALR 返回异常前主程序
  - 指令 jalr x0, x31, 0 将 PC ← x31，即 PC = 0x00000054
  - 波形中 PC 成功从 0x304 → 0x54，异常处理完毕


#### 22. 指令：LUI x11, 0x00001（PC = 88）
**机器码**：0x000015B7

**功能**：将 0x00001 左移 12 位后写入 x11

**操作**：x11 = 0x00001000

**中间信号**：
ALUControl：0001（LUI路径）
ALUOut：0x00001000
RegWrite：1；waddr = x11，wdata = 0x00001000

- 执行前：
  - x11 = 未定义
  - PC = 0x00000054
- 执行后：
  - x11 = 0x00001000
  - PC = 0x00000058

<img src="image-19.png"  width="50%" height="auto">

#### 23. 指令：ADDI x11, x11, -2048（PC = 92）
**机器码**：0x80058593

**功能**：将立即数 -2048 加到 x11 中，结果写回 x11

**操作**：x11 = x11 - 2048 = 0x00001000 + 0xFFFFF800 = 0x00000800（Cause寄存器地址）

**中间信号**：
ALUControl：0000（加法）
ALUOut：0x00000800（Cause 映射地址）
RegWrite：1；waddr = x11，wdata = 0x00000800

- 执行前：
  - x11 = 0x00001000
  - PC = 0x00000058
- 执行后：
  - x11 = 0x00000800
  - PC = 0x0000005c
  
<img src="image-20.png"  width="50%" height="auto">


#### 24. 指令：ADDI x10, x0, 0（PC = 96）
**机器码**：0x00000513

**功能**：将立即数 0 加到 x0 中，结果写回 x10

**操作**：x10 = 0 + 0 = 0

**中间信号**：
ALUControl：0000（加法）
ALUOut：0x00000000
RegWrite：1；waddr = x10，wdata = 0x00000000

- 执行前：
  - x10 = 0x80000000
  - PC = 0x0000005c
- 执行后：
  - x10 = 0x00000000
  - PC = 0x00000060

<img src="image-21.png"  width="50%" height="auto">

#### 25. 指令：ECALL（PC = 100）
**机器码**：0x00000073

**功能**：执行环境调用（Environment Call），在本实验中被设计为停机指令，使 CPU 停止执行。

**中间信号**：
Halt 信号：输出 Halt = 1，CPU 停止运行
RegWrite / ALU 无操作（作为伪指令处理）

<img src="image-22.png"  width="50%" height="auto">


## **六、实验思考**
### **1. 遇到的问题及解决方法**
**1. 问题描述**：对多周期 CPU 中每条指令在多个状态（周期）下的执行流程不够了解，导致状态设置和控制信号不协调完整，无法正确执行指令。

**解决方法**：先通过教材和资料明确了多周期 CPU 将指令分解成的阶段，熟悉了每个状态下应产生的控制信号，在基本编写完代码后逐个调试了 waddr, wdata, ALU_result, PCWrite 等进行验证，借助 AI 工具辅助完成了仿真测试代码的设计和检测。

**2. 问题描述**：在实现异常服务功能这一扩展要求时遇到了非常多问题，例如：异常跳转不生效、程序死循环、返回地址错误等等。

**解决方法**：
- **对于异常跳转不生效**：检查后推测是 EPC 在写入后没有在 JALR 状态被使用，通过修改 TrapReturn 的控制实现了 PC 的处理切换。
- **对于状态机异常处理进入死循环**：用 ControlUnit 中的 TrapReturn 控制信号，指示异常返回阶段的状态；在 cpu_top 中加入 EPC 寄存器专门保存 PC+4，用于异常返回；在 S_TRAP_WB 状态中使用 RegWrite 写入 x31；在 JALR 阶段根据 TrapReturn 控制信号将 PC ← EPC 恢复程序流程；在返回前执行对 Cause 的清零。进行上述检查和修改后解决了问题。
- **对于 JALR 指令无法正确返回，出现回到错误位置或跳转失败**：在 ControlUnit 的 S_EX_JAL 状态中添加了 is_jalr 标志位；在 cpu_top 中 PCWrite 控制逻辑中加入 if (is_jalr) 分支确保跳转地址按规范对齐。
- **对于仿真无法停止**：在 opcode == 7'b1110011 或未识别指令中进入 S_HALTED 停机状态；在 S_HALTED 状态中输出 Halt = 1 并锁死 next_state = S_HALTED。

**3. 问题描述**：内存模块 Memory 读写访问不一致，数据区（从 0x400 开始）读写结果正确，但 Cause 寄存器访问有异常。

**解决方法**：读地址判断使用 addr[10:2]，但 Cause 映射地址是 0x800，要特殊处理；在写入逻辑中区分了 causeWrite 和普通 MemWrite；验证了仿真波形中 write_data=0 写入 addr=0x800 时，causeReg 成功清零。代码逻辑修改如下：

```verilog
if (addr == 32'h00000800) begin  // 访问Cause寄存器
    read_data = causeReg;
else                             // 访问一般存储单元（字对齐）             
  read_data = mem[addr[10:2]];
```

**4. 问题描述**：指令寄存器 IR 未能及时获取指令，导致 ControlUnit 解析有问题。

**解决方法**：检查发现错误原因是 IRWrite 控制信号未在 S_IF 阶段拉高，导致 memory_out 未能加载到 IR；因此在 ControlUnit 中 S_IF 状态设置：IRWrite = 1'b1 ; MemRead = 1'b1; top.v 中的 if (IRWrite) 处写 IR <= memory_out。从而验证了波形中 IR 在 PC+4 周期加载的是 memory_out 的内容，且下一状态能正确识别 opcode。


### **2. 实验心得**
- 多周期 CPU 在硬件资源占用上比单周期节省，采用状态机控制，提高了时钟频率。通过本次 32 位 RISC-V 多周期 CPU 的设计实验，从逐步熟悉 Verilog 语言到最终实现多阶段指令执行和异常机制控制，我对计算机体系结构和处理器控制流程有了系统性理解。
  
- 实验过程中，我查阅资料、阅读指令架构手册，学习了 RISC-V 各类指令的操作特性和多周期的执行机制。通过逐条指令仿真，我掌握了取指、译码、执行、访存、写回在多周期 CPU 中分别对应的状态划分，对控制信号生成的精确性和时序性有了深刻体会。
  
- 在模块搭建和功能实现过程中，起初我对状态机控制逻辑、多周期的中间寄存器 A、B、ALUOut、IR 等的应用都不熟悉。通过本次实验我掌握了状态转移设计方法、 ALU 控制信号映射、异常 Cause 寄存器管理方法等内容，系统地完成了一个有真实功能的多周期处理器设计。
  
- 在调试过程中我遇到了指令执行顺序错误、数据回写出错、 PC 无法跳转等各类问题，通过对比波形图检查关键控制信号，如 PCWrite、RegWrite、Trap 等，我成功定位了问题并加以修正，例如 JALR 返回地址的错误是由于 EPC 寄存器未正确写入。这一过程显著提升了我借助仿真工具 debug 的能力。
  
- 本项目整体难度和复杂度相较于前一个单周期实验有较大提升，从状态转移设计、组合逻辑控制到异常跳转处理，都需要兼顾逻辑准确和时序协调，锻炼了我完整思考系统设计、模块集成的能力。
  
- 最后，非常感谢老师、助教和同学在实验过程中给予我的帮助与指导。这一实验不仅加深了我对多周期 CPU 设计的理解，也为后续更复杂的流水线体系结构设计打下了基础。

## **七、附录（文件清单）**
<img src="image-23.png"  width="50%" height="auto">
