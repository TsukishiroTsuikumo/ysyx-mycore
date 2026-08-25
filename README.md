# ysyx-mycore

`ysyx-mycore` 是一个 RV32IM 处理器与验证项目。当前版本点以 `main` 中的
五级单发射流水线为基础，原位接入 ICache、DCache、AXI4 互连和 AXI RAM；
处理器实现仍只有 `dut/mycore/mycore.v` 中的 `mycore`，系统集成顶层为
`dut/mycore_system.v` 中的 `mycore_system`。

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

- `mycore` 保留原有顺序单发射五级流水、hazard/stall/flush 控制和标量访存接口。
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

lane 0 使用每条总线的低位且永远是较老指令；当前单发射版本把 lane 1 固定为
零。验证 monitor 按 lane 0、lane 1 的顺序生成退休 transaction，因此后续微架构
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

这个版本点是后续微架构演进的共同基础。后续版本继续原位修改同一个
`mycore.v`，并持续复用 `mycore_system`、Cache/AXI/RAM 和上述退休接口；不会
新增并行存在的完整 CPU top。每个版本点都必须能独立 checkout、构建和通过
对应门禁，DUT 的纯 Verilog 约束始终保持不变。
