# 控制流重定向遇到流水线暂停的Bug报告

## 问题摘要

当控制流指令产生跳转重定向时，如果该指令所在的流水级正好因为后级暂停而不能继续向后流动，旧逻辑仍然会立即刷新前端并更新PC。结果是：跳转目标路径开始执行，但产生跳转的那条指令本身没有进入后续流水级，也不会retire，导致 DUT的retire序列和C model的参考序列从这一点开始错位。

最初观察到的失败现象如下：

```text
sb_loop_test.log:
PROGRAM_SCORE PASS=369 FAIL=4634 MISSING=0 EXTRA=0
FirstError:
pc mismatch exp=0x00000068 act=0x0000012c
```

在`PC=0x68`处的指令是：

```text
0x00000068: 0c40006f    jal x0, 0x12c
```

DUT已经跳转到 `0x12c`，但`0x68`这条`jal`没有retire。C model的行为是正确的：跳转指令本身也必须先retire，然后才轮到跳转目标路径上的指令。

## 相关流水线结构

当前DUT中控制流指令的处理位置如下：

- `jal`在ID阶段即可得到跳转目标并产生redirect。
- `jalr`在ID阶段译码，但目标地址依赖加法器结果，因此在EX阶段产生redirect。
- 条件分支同样在EX阶段通过加法器输出的`branch_cd`判断是否跳转。
- `flush_sig[0]`用于刷新取指队列。
- `flush_sig[2]`用于清空ID/EX流水线寄存器。
- `hzd_stall[1]`表示ID到EX不能前进。
- `hzd_stall[2]`表示EX到MEM不能前进。

关键约束是：**产生 redirect的指令必须能同步进入下一流水级，否则redirect不能生效。** 如果只更新PC和刷新前端，而指令本身被挡在原流水级甚至被flush清掉，就会出现“跳转发生了，但跳转指令没有retire”的错误。

## 根因分析

旧逻辑中，redirect条件主要依赖“当前是否为跳转指令”和“当前指令是否valid”，但没有检查产生redirect的流水级是否真的能够向后流动。

### JAL 的问题

`jal`在ID阶段产生redirect。若同一拍`hzd_stall[1]` 为1，说明ID阶段的指令不能进入ID/EX。

旧逻辑在这种情况下仍然允许`jal`更新PC并flush前端，于是：

1. PC被改成跳转目标地址。
2. fetch queue被flush。
3. 但`jal`没有进入 ID/EX。
4. 后续retire流中缺失这条`jal`。
5. scoreboard看到的下一条DUT retire指令直接变成目标路径指令，例如`0x12c`，而C model期望的仍然是`0x68`的`jal`。

因此，`jal`的redirect必须额外满足ID阶段能够进入EX：

```text
!hzd_stall[1]
```

### JALR 和条件分支的潜在同类问题

`jalr`和条件分支在EX阶段产生redirect。若同一拍 `hzd_stall[2]`为1，说明EX阶段指令不能进入EX/MEM。

如果此时仍允许redirect生效，就可能出现：

1. PC被更新到跳转目标。
2. 前端被flush。
3. `flush_sig[2]`清空ID/EX。
4. 产生redirect的`jalr`或条件分支没有进入EX/MEM。
5. 该控制流指令从retire流中消失。

这和`jal`的bug本质相同，只是发生在EX到MEM的边界。因此，EX阶段产生的redirect必须额外满足EX阶段能够进入 MEM：

```text
!hzd_stall[2]
```

## 修复方案

最小修复原则是：不改PC写入时序，不改fetch queue的flush/drop 机制，不改变`jal`、`jalr`、条件分支各自所在的解析阶段，只给redirect增加“源流水级可以前进”的约束。

修复后的控制条件如下：

```verilog
wire is_jal_if = is_jal_id && instr_valid && valid[0] && !hzd_stall[1];

.is_cd_jp(is_cd_jp_ex && valid_id_ex && valid[1] && !hzd_stall[2]),
.is_jal(is_jal_if),
.is_jalr(is_jalr_id_ex && valid_id_ex && valid[1] && !hzd_stall[2]),
```

其中：

- `jal`只有在ID指令有效、IF/ID valid有效、且ID/EX能接收时才允许redirect。
- `jalr`只有在ID/EX指令有效、对应valid有效、且EX/MEM能接收时才允许redirect。
- 条件分支同理，只有在EX阶段指令能进入EX/MEM时才允许redirect。

这样可以保证：**只要PC被redirect，产生redirect的那条指令也一定继续沿流水线向retire路径前进。**

## 为什么不修改 flush 周期的取指逻辑

曾经考虑过flush周期内是否需要特殊分配fetch queue entry，但这不是根因。

当前设计中，跳转目标地址是在redirect后写入PC，下一拍才会作为新的PM请求地址发出。因此，flush发生当拍即使还有旧PC的取指响应或请求，也属于错误路径，应由flush/drop机制处理。

真正的问题不是flush周期有没有分配队列项，而是redirect太早生效：产生redirect的指令本身还没有被后级接收。修复点应该放在redirect条件上，而不是重写fetch queue的整体时序。

## 影响范围

受影响的是所有“产生redirect的流水级可能被后级stall阻塞”的控制流指令：

- `jal`：ID阶段redirect，受`hzd_stall[1]`影响。
- `jalr`：EX阶段redirect，受`hzd_stall[2]`影响。
- 条件分支：EX阶段redirect，受`hzd_stall[2]`影响。

如果不修复，典型现象是：

- DUT实际跳到了正确目标地址；
- 但跳转指令本身没有retire；
- scoreboard首个错误通常表现为PC mismatch；
- 后续指令序列整体错位，导致大量fail。

## 验证结果

原始失败用例修复后通过：

```text
make run TEST=mem_image_test MEM_FILE=./csrc/image/sb_loop_test.mem
PROGRAM_SCORE PASS=5003 FAIL=0 MISSING=0 EXTRA=0
```

相关回归也通过：

```text
sb_loop_test.log: UVM_INFO test_bench/test/program_test/program_scoreboard.svh(264) @ 29218000: uvm_test_top.env.scoreboard [PROGRAM_SCORE] PASS=5003 FAIL=0 MISSING=0 EXTRA=0


complex_test_image.log: UVM_INFO test_bench/test/program_test/program_scoreboard.svh(264) @ 26364000: uvm_test_top.env.scoreboard [PROGRAM_SCORE] PASS=5002 FAIL=0 MISSING=0 EXTRA=0


main_image.log: UVM_INFO test_bench/test/program_test/program_scoreboard.svh(264) @ 26564000: uvm_test_top.env.scoreboard [PROGRAM_SCORE] PASS=5003 FAIL=0 MISSING=0 EXTRA=0


sb_test_image.log: UVM_INFO test_bench/test/program_test/program_scoreboard.svh(264) @ 39552000: uvm_test_top.env.scoreboard [PROGRAM_SCORE] PASS=5002 FAIL=0 MISSING=0 EXTRA=0


sb_fail_test_image.log: UVM_INFO test_bench/test/program_test/program_scoreboard.svh(264) @ 37616000: uvm_test_top.env.scoreboard [PROGRAM_SCORE] PASS=5002 FAIL=0 MISSING=0 EXTRA=0


sb_loop_test_image.log: UVM_INFO test_bench/test/program_test/program_scoreboard.svh(264) @ 29390000: uvm_test_top.env.scoreboard [PROGRAM_SCORE] PASS=5003 FAIL=0 MISSING=0 EXTRA=0

Summary:
  Passed Tests Count: 6
  Failed Tests Count: 0
```

最新完整regression脚本也已经跑通，说明该修复没有破坏现有core-only和program-image测试流程。
