# ysyx-mycore

`ysyx-mycore` 是一个 RV32IM 处理器与验证项目。当前第二个版本点在已经接入
ICache、DCache、AXI4 和 AXI RAM 的五级单发射版本上，继续原位把
`dut/mycore/mycore.v` 演进为固定双发射顺序核。仓库中没有 width-1 配置或
另一份并行 CPU；完整处理器顶层始终只有 `mycore`，系统集成
顶层仍为 `dut/mycore_system.v` 中的 `mycore_system`。

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

- `mycore` 是固定两宽的顺序发射/顺序退休核，沿用原五级流水的数据通路和
  hazard/stall/flush 语义；前端每次接收 128-bit 指令 cache line，并向后端提供
  两条连续指令。
- 两条互不依赖的简单整数指令可以同周期发射和退休。pair RAW 必须拆分；WAR、
  WAW 可成对流动且 WAW 的年轻 lane 最终胜出；x0 不形成伪相关也不会被写入。
- RV32M、load/store、控制流和 FENCE 使用 lane 0 的标量路径；数据访存接口仍只
  允许一笔顺序 transaction，不改变 DCache/AXI 协议。
- ICache、DCache 默认均为 16-byte cache line、16 sets、4 ways；DCache 支持
  dirty write-back，ICache 提供显式 invalidate 输入。
- Cache line 通过 32-bit AXI4 的四拍 `INCR` burst 传输。I/D read 共用仲裁器，
  DCache write 独立进入 decoder；每个 adapter 最多保留一个 outstanding
  transaction。
- 默认 RAM window 为 `0x0000_0000` 起始的 16 MiB；
  `0x1000_0000` 的保留 MMIO window 和 unmapped 地址由 error slave 返回错误。
- AXI `SLVERR/DECERR` 当前只形成 sticky diagnostic，不触发架构异常或 trap。

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
升级不需要再读取流水级内部层次名。

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

这个版本点从第一个“单发射五级流水 + Cache/AXI/RAM”提交连续演进而来。下一
版本会在同一个 `mycore.v` 内把顺序后端进一步替换为有界 OoO 后端，并持续复用
`mycore_system`、Cache/AXI/RAM 和上述退休接口；不会新增并行存在的完整 CPU
top。每个版本点都必须能独立 checkout、构建和通过对应门禁，DUT 的纯 Verilog
约束始终保持不变。
