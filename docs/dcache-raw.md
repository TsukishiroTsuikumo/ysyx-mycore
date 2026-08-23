# BUG

## BUG信息

- 现象：启用Dcache后执行`mem_image_test`测试程序，大量DMEM读取返回NOP预填充值（`0x00000013`）而非之前 store 写入的数据。Dcache的Read After Write失效。

- 是否修复：已修复

## BUG分析

### 错误特征

```
pass=78 fail=148 dmem_checked=22
```

典型错误：

```
dmem write mismatch pc=0x0000017c addr=0x000fffd4
  exp_wdata=0x0000004e act_wdata=0x00000039
dmem read data mismatch pc=0x00000180 addr=0x000fffd4
  exp=0x0000004e act=0x00000013
```

- Load 从已 store 过的地址读取，返回 MEM 预填充的 NOP 值（0x13）
- Store 写入的数据是**上一次请求的旧数据**而非当前计算结果

### 根因：`cpu_wstrb_line` / `cpu_wdata_line` 使用旧值

Dcache 中对 cache line 的**部分写入**（store 合并到 cache line）在 `Dcache.v` 中通过 `cpu_wstrb_line` 和 `cpu_wdata_line` 控制写入字节和写入数据。这两个信号在组合逻辑中由 **`req_wstrb_q`、`req_wdata_q`、`req_offset_q`**（上一次请求的寄存器值）计算得出：

```verilog
// Dcache.v (原代码)
always @(*) begin
    cpu_wstrb_line = {DM_LINE_BYTES{1'b0}};
    cpu_wdata_line = {DM_LINE_WIDTH{1'b0}};
    for (byte_idx = 0; byte_idx < 4; byte_idx = byte_idx + 1) begin
        line_byte_idx = req_offset_q_ext;       // 旧的 offset！
        line_byte_idx = line_byte_idx + byte_idx;
        if (req_wstrb_q[byte_idx] && ...) begin // 旧的 strobe！
            cpu_wstrb_line[line_byte_idx] = 1'b1;
            cpu_wdata_line[...] = req_wdata_q[...]; // 旧的数据！
        end
    end
end
```

两种 store 场景的行为对比：

**Miss 场景（该 cache line 首次被访问）：**

| 周期 | 状态 | 行为 |
|------|------|------|
| N | IDLE | `cpu_write_fire`，`set_wr_req` 有效，但 `hit=0` → `wr_hit_out=0`，不写入 |
| N (posedge) | → RDMEM | `req_wstrb_q`/`req_wdata_q` 更新为新请求的值 |
| ... | RDMEM → BUSY | refill 完成后，BUSY 周期用**已更新的** `req_*_q` 计算写入 → ✅ 正确 |

**Hit 场景（同一 cache line 的后续 store）：**

| 周期 | 状态 | 行为 |
|------|------|------|
| N | IDLE | `cpu_write_fire`，`set_wr_req` 有效，`hit=1` → `wr_hit_out=1` |
| N (posedge) | → BUSY | **同一 posedge**：`req_*_q` 更新 + cache line 写入 |
| | | `cpu_wstrb_line`/`cpu_wdata_line` 仍使用**更新前**的 `req_*_q` → ❌ **旧数据被写入** |

### 时序图

```
            IDLE                 BUSY
           ┌──────┐           ┌──────┐
    clk    │      │           │      │
           │      │           │      │
wr_req_in  ───────────────────────────────────
           │      └───────────│      │
           │                 │      │
wr_hit_out ───────────────────────┘      │
           │      ┌───────────│      │
           │      │           │      │
cpu_wstrb  ──────────────────────────────  ← 来自旧 req_*_q
 _line     │ ●●●●●│●●●●●●●●●●●│      │     ● = 旧数据
           │      │           │      │
req_wstrb_q ──────────────────────────────
           │      │ ●●●●●●●●●●│      │     ● = 新数据(但来不及用)
           │      │           │      │
cache_line  ────────────┐            │     写入 ● 旧数据到 cache line
 write    │      │      ●│●●●●●●●●●●│
                         写入位置：旧 offset
                         写入数据：旧 wdata
```

在 Hit 场景下，`cpu_wstrb_line`/`cpu_wdata_line` 在同一个时钟边沿被采样写入 cache line，而此时 `req_wstrb_q`/`req_wdata_q`/`req_offset_q` 的 NBA 更新尚未生效——写入的是**上一次请求**的 strobe、数据和偏移量。

## 修复方式

在 `Dcache.v` 中，当处于 IDLE 状态且有请求时，直接从 `dm_req_*_in` 输入端口计算 `cpu_wstrb_line` 和 `cpu_wdata_line`：

```verilog
// Dcache.v (修复后)
always @(*) begin
    cpu_wstrb_line = {DM_LINE_BYTES{1'b0}};
    cpu_wdata_line = {DM_LINE_WIDTH{1'b0}};

    if (current_state == IDLE && (dm_req_wvalid_in || dm_req_rvalid_in)) begin
        // IDLE 状态：使用当前 dm_req 输入端口的值
        for (byte_idx = 0; byte_idx < 4; byte_idx = byte_idx + 1) begin
            line_byte_idx = dm_req_addr_in[OFFSET_WIDTH-1:0];
            line_byte_idx = line_byte_idx + byte_idx;
            if (dm_req_wstrb_in[byte_idx] && line_byte_idx < DM_LINE_BYTES) begin
                cpu_wstrb_line[line_byte_idx] = 1'b1;
                cpu_wdata_line[line_byte_idx*8 +: 8] = dm_req_wdata_in[byte_idx*8 +: 8];
            end
        end
    end
    else begin
        // 非 IDLE 状态（BUSY / RDMEM 等）：使用已捕获的 req_*_q
        for (byte_idx = 0; byte_idx < 4; byte_idx = byte_idx + 1) begin
            line_byte_idx = req_offset_q_ext;
            line_byte_idx = line_byte_idx + byte_idx;
            if (req_wstrb_q[byte_idx] && line_byte_idx < DM_LINE_BYTES) begin
                cpu_wstrb_line[line_byte_idx] = 1'b1;
                cpu_wdata_line[line_byte_idx*8 +: 8] = req_wdata_q[byte_idx*8 +: 8];
            end
        end
    end
end
```

### 附加修复：`one_set.v` 中 `line_time` 初始化

`line_time` 数组（LRU 时间戳）在复位时未初始化，导致仿真中出现 X 值，影响 victim way 选择。修复：复位时将 `line_time` 全部清零。

## 涉及文件

| 文件 | 修改内容 |
|------|----------|
| [dut/mem/Dcache.v](../dut/mem/Dcache.v) | `cpu_wstrb_line`/`cpu_wdata_line` 在 IDLE 状态使用当前 `dm_req_*_in` |
| [dut/mem/one_set.v](../dut/mem/one_set.v) | 复位时初始化 `line_time` 数组 |

## 验证结果

| 测试 | 修复前 | 修复后 |
|------|--------|--------|
| `mem_image_test` | pass=78 fail=148 dmem_checked=22 | **pass=155 fail=0 dmem_checked=89** |
| `calc_test` | — | **pass=55 fail=0** |
