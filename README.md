# ysyx-mycore

`ysyx-mycore` 是一个 RV32IM 处理器与验证项目。当前第三个版本点从五级单发射
版本接入 ICache、DCache、AXI4 和 AXI RAM，再经固定双发射顺序版本，继续在
同一个 `dut/mycore/mycore.v` 内原位演进为有界乱序执行核。仓库中没有 width-1
配置、旧顺序核副本或另一份并行 CPU；完整处理器顶层始终只有 `mycore`，系统
集成顶层仍为 `dut/mycore_system.v` 中的 `mycore_system`。

## 当前架构

```text
                         +---------+
                    +--->| ICache  |---+
                    |    +---------+   |     +----------------+
  mycore (RV32IM) --+                  +---->| AXI read arbiter|---+
                    |    +---------+   |     +----------------+   |
                    +--->| DCache  |---+                          v
                         +---------+---- AXI write ----------> decoder
                                                                 |  |
                                                          AXI RAM   error slave
```

`mycore` 内部保持一层扁平连线，控制/状态和原执行单元之间的数据流为：

```text
instr_queue -> decoder x2 -> hazard -> RAT -> PRF read -> RS
                              |        |                 |---> adder/alu/shifter/imu x2 --+
                              |        |                 |---> multiplier/divider + tracker |
                              |        |                 +---> lsu(AGU) -> LSQ -> DCache     |
                              |        +-----------------------------------------------+      |
                              +-> ROB <---------------- CDB x2 <------------------------+------+
                                  |             |       |
                                  |             +------> PRF write / RS wakeup
                                  +-> 双顺序退休；mispredict -> IQ/RAT/RS/LSQ recovery
```

- `mycore` 保留固定两宽、128-bit 指令 cache-line 前端与顺序双退休接口，把顺序
  后端替换成有界 OoO 后端：8-entry ROB、48-entry PRF、12-entry RS 和 8-entry
  LSQ；重命名同时处理同包 RAW/WAW/WAR，x0 不分配物理目的寄存器。
- `mycore.v` 仍按 IF/译码/重命名/调度/执行/CDB/退休的扁平顺序展开；两个整数
  lane、单个 RV32M lane 和单个 LSU 都直接实例化原 `adder`、`alu`、`shifter`、
  `imu`、`multiplier`、`divider`、`lsu`。RAT/PRF、ROB、RS、LSQ、`hazard` 与
  `controller` 只保存必要状态、产生调度控制并通过显式信号驱动这些单元，仓库中
  没有包住整套执行单元的 backend 或 execute-lane wrapper。顺序核的 ID/EX、
  EX/MEM、MEM/WB 职责分别演进为 RS、LSQ、CDB+ROB，而不是并行保留一份旧流水核。
- 整数 ALU、12-cycle RV32M 和 load 可以乱序完成，但 ROB 始终按程序次序退休，
  每周期最多退休 lane 0、lane 1 两条且 lane 1 不会孤立出现。公开退休总线因此
  仍可作为与具体流水级无关的架构 oracle。
- store 只有到达 ROB head 才能外发并等待写响应；load 等待所有更老的 store、
  未决控制流和 FENCE 消除。branch/JAL/JALR 在 head 恢复 RAT/空闲表并重定向，
  错路指令不得退休或产生数据访存；FENCE 在 head 单独退休。
- 分离的标量 DM 接口及 DCache/AXI/Mem 系统保持不变，任一时刻最多保留一笔
  外部数据 transaction；乱序范围不会泄漏为新的 cache 或总线协议。
- ICache、DCache 默认均为 16-byte cache line、16 sets、4 ways；DCache 支持
  dirty write-back，ICache 提供显式 invalidate 输入。
- Cache line 通过 32-bit AXI4 的四拍 `INCR` burst 传输。I/D read 共用仲裁器，
  DCache write 独立进入 decoder；每个 adapter 最多保留一个 outstanding
  transaction。
- 默认 RAM window 为 `0x0000_0000` 起始的 16 MiB；
  `0x1000_0000` 的保留 MMIO window 和 unmapped 地址由 error slave 返回错误。
- AXI `SLVERR/DECERR` 当前只形成 sticky diagnostic，不触发架构异常或 trap。
- 当前执行契约要求 load/store 自然对齐，split-DM response valid 是单周期完成脉冲；
  跨 cache-line 的非对齐 store 不在支持范围内。

`mycore_system` 内只实例化一颗 `mycore`。UVM wrapper 通过 `use_cache` 在两种
验证路径间切换：program/memory-image 测试经过完整 Cache/AXI/RAM，core-only
模块测试使用既有 direct PM/DM agent；两条路径不会重复实例化处理器。

## 稳定验证接口

`mycore` 和 `mycore_system` 都暴露相同的扁平双槽退休接口：

- `retire_valid_out[1:0]`
- `retire_pc_out[63:0]`、`retire_instr_out[63:0]`
- `retire_rd_write_out[1:0]`
- `retire_rd_addr_out[9:0]`、`retire_rd_data_out[63:0]`

lane 0 使用每条总线的低位且永远是较老指令；lane 1 只会与 lane 0 一起有效。
验证 monitor 按 lane 0、lane 1 的顺序生成退休 transaction，因此后续微架构
升级不需要再读取流水级内部层次名。为保持 main 以来的 trace 契约，
`retire_rd_write_out` 表示指令具有 decoded `rd` 意图；写 `x0` 时该位仍为 1、
地址和数据均为 0，但 x0 不分配物理寄存器且架构状态始终不可写。

所有 `dut/**` 文件必须使用 IEEE 1364-2005 Verilog（`.v/.vh`）。SystemVerilog、
UVM、assertion 和协议 checker 只允许放在 `test_bench/**`。

## 构建与验证

基础依赖为 GNU Make、Python 3、C++17 compiler 和 Verilator。UVM 流程还需要
Accellera UVM 2020.3.1，并通过 `UVM_HOME` 指向源码目录；从 `csrc/` 编译程序
时需要 `riscv64-unknown-elf-*` toolchain、`xxd` 和 `awk`。

先运行 DUT 语言门禁。第一条命令执行快速词法检查，第二条还会强制 Verilator
以 IEEE 1364-2005 模式只编译 DUT：

```sh
make dut-syntax
make lint-dut
```

参考模型、辅助脚本和独立子系统测试：

```sh
make cmodel-test
python3 -m unittest scripts.test_regression scripts.test_coverage
make cache-test
make axi-test
```

Cache 的 active UVM gate：

```sh
export UVM_HOME=/path/to/uvm-core
make cache-uvm-test
```

固定双发射核有两个不依赖 UVM 的轻量阻塞门禁：

```sh
make dual-test
make dual-system-test
```

`dual-test` 从 `mycore` 的公开 128-bit PM、标量 DM 和扁平退休端口做精确
retire/memory oracle 对比，覆盖真实双退休、pair/旧流水 RAW、WAR、WAW、x0、
RV32M、带 backpressure 的 load/store、branch/JAL/JALR 错路清除和 FENCE。
`dual-system-test` 只实例化 `mycore_system(use_cache=1)`，经真实 ICache、DCache、
AXI 和 RAM 执行短程序，并要求观察到 I/D 两种 AXI owner ID、DCache hit 后不重复
refill、脏替换写回、双退休且无 bus fault。对应成功标记为
`DUAL_CORE_TEST PASS` 和 `DUAL_SYSTEM_TEST PASS`。

这两道顺序双发射 gate 在 OoO 版本继续保留，作为“同一个核原位演进”而非重写
的兼容性回归。第三版本点另有两道只读取稳定公开接口的验收门禁：

```sh
make ooo-test
make ooo-system-test
make ooo-unit-test
```

`ooo-test` 用精确的 lane 0 后 lane 1 退休 oracle 和最终寄存器/内存状态覆盖
同包 RAW/WAW/WAR、x0、ROB 压力、RV32M、LSQ/store-head/FENCE 次序、控制流恢复
和 DM backpressure。它以“年轻 load 请求严格早于老 12-cycle M 退休”作为无需
读取 ROB/RS 内部层次的 OoO 证据。`ooo-system-test` 只实例化
`mycore_system(use_cache=1)`，经真实 Cache/AXI/RAM 检查 M 与年轻 load/整数、
store/load、taken control、双退休、AXI I/D owner ID、DCache 脏替换写回且无
sticky bus fault。成功标记为 `OOO_CORE_TEST PASS` 和 `OOO_SYSTEM_TEST PASS`。
`ooo-unit-test` 进一步分别隔离检查 RAT/PRF 的双重命名与恢复、ROB/RS 的乱序完成
和顺序退休/唤醒选择，以及 LSQ/CDB/RV32M tracker 的 barrier、背压、flush-drain
和固定延迟行为；三个成功标记分别为 `OOO_RAT_TEST PASS`、
`OOO_ROB_RS_TEST PASS`、`OOO_LSQ_EXEC_TEST PASS`。

完整处理器 smoke test 会预加载 AXI RAM，并确保取指和数据访问都经过 cache/AXI
路径：

```sh
export UVM_HOME=/path/to/uvm-core
make build
make run-only \
  TEST=mem_image_test \
  MEM_FILE=test_bench/programs/axi_smoke.mem \
  TARGET_COMMITS=32 \
  TIMEOUT_CYCLES=20000 \
  SIM_TIMEOUT=50000
```

确定性的 RV32IM/FENCE 覆盖程序可用下列命令运行：

```sh
make run-only \
  TEST=mem_image_test \
  MEM_FILE=test_bench/programs/rv32im_coverage.mem \
  TARGET_COMMITS=67 \
  REQUIRE_ISA_COVERAGE=1 \
  TIMEOUT_CYCLES=30000 \
  SIM_TIMEOUT=100000
```

更细的 AXI 和 Cache 测试范围及 PASS marker 见
[`test_bench/axi/README.md`](test_bench/axi/README.md)、
[`test_bench/cache/README.md`](test_bench/cache/README.md) 和
[`test_bench/cache_uvm/README.md`](test_bench/cache_uvm/README.md)。

这个版本点从第一个“单发射五级流水 + Cache/AXI/RAM”提交，经第二个“固定顺序
双发射”提交连续演进而来；第三个提交只在同一个 `mycore.v` 内替换后端，持续
复用 `mycore_system`、Cache/AXI/RAM 和上述退休接口，没有新增并行存在的完整
CPU top。三个版本点都应能独立 checkout、构建并通过各自门禁，DUT 的纯
Verilog-2005 约束始终保持不变。
