# Dual-Issue In-Order Intermediate Core

## Status and scope

This document defines the phase-4 intermediate microarchitecture between the
current single-issue pipeline and the later out-of-order core.  It is provided
as a standalone `mycore_dual` top so it can be verified without modifying the
stable `mycore.v` or colliding with the AXI/cache integration work.

- `dut/mycore/front/fetch_frontend.v`
- `dut/mycore/controller/issue_control.v`
- `dut/mycore/fu/execute_lane.v`
- `dut/mycore/reg/perf_counters.v`
- `dut/mycore/mycore_dual.v`
- `test_bench/dual_issue/dual_issue_core_tb.sv`
- `test_bench/dual_issue/flist_dual.f`

The target is two-wide, in-order issue and two-wide, in-order retirement for
RV32IM.  This phase does not add register renaming, a reorder buffer,
out-of-order completion, speculative loads, exceptions, interrupts, CSR or an
MMU.

`mycore_dual` currently uses one ordered backend bundle.  A non-memory bundle
retires on the following edge; an LSU bundle holds the backend until its
response.  This is intentionally conservative: while memory is stalled, no
younger instruction enters execution.  Control redirects are calculated when
the lane-0 control instruction issues, and all controls are serialized, so no
younger lane exists to kill in that bundle.

This implementation therefore does **not** claim to verify a future
multi-stage pipeline's EX-over-ID redirect priority, nor a state with a branch
in EX while an older LSU remains in MEM.  Those properties become applicable
only when `mycore.v` is widened into distinct ID/EX, EX/MEM and MEM/WB stages.
The standalone core instead verifies the architectural phase-4 contract:
strict ordered issue/retirement, no wrong-path retirement, memory
backpressure, genuine two-wide progress and identical width-1/width-2 traces.

## Why the frontend uses 128-bit lines

The existing core-to-ICache response contains one 32-bit instruction.  Its
absolute supply limit is therefore one instruction per cycle, and the current
non-pipelined ICache returns a hit approximately once every two cycles.  A
second decoder or ALU behind that interface could only issue two instructions
occasionally after the queue had accumulated work during a backend stall.

The ICache already stores and refills 128-bit cache lines.  Phase 4 therefore
returns the complete line to `fetch_frontend`:

```text
one 128-bit line / two hit cycles = four instructions / two cycles
                                    = two instructions per cycle
```

A 64-bit response without a pipelined ICache would still average only one
instruction per cycle and is not sufficient for phase-4 acceptance.

Within a response, the word mapping is little-endian and matches the memory
line representation:

| Instruction address | Response bits |
|---|---:|
| `line_base + 0` | `[31:0]` |
| `line_base + 4` | `[63:32]` |
| `line_base + 8` | `[95:64]` |
| `line_base + 12` | `[127:96]` |

## Instruction class encoding

`issue_control` and `execute_lane` use the following fixed encoding:

| Value | Name | Instructions | Pairing rule |
|---:|---|---|---|
| `3'd0` | `SIMPLE_INT` | RV32I OP, OP-IMM, LUI, AUIPC | May pair with another `SIMPLE_INT` |
| `3'd1` | `MULDIV` | RV32M MUL/DIV/REM family | Lane 0, single issue |
| `3'd2` | `LSU` | LOAD and STORE | Lane 0, single issue |
| `3'd3` | `CONTROL` | BRANCH, JAL, JALR | Lane 0, single issue |
| `3'd4` | `INVALID` | Unsupported or illegal encoding | Never dual issue |

These values must remain synchronized when the existing decoder is extended.

## `fetch_frontend`

### Request and response contract

- `pm_req_valid`, `pm_req_ready`, and `pm_req_addr` form the request handshake.
- `pm_req_addr` is always 16-byte aligned.
- Every accepted request produces exactly one ordered `pm_resp_valid` pulse.
- `pm_resp_data` contains a complete 128-bit line.
- The response channel has no ready signal and must not be backpressured.
- Zero-cycle responses, in which request and response occur together, are
  supported.
- `QUEUE_DEPTH` must be a power of two of at least two.

The frontend has three ring pointers:

- allocation pointer for accepted requests;
- response pointer for ordered returned lines;
- read pointer for the oldest line visible to decode.

It can hold requested but not-yet-returned entries without exposing them to
decode.

### Decode outputs and consumption

`instr0/pc0` is always the oldest instruction.  `instr1/pc1`, when valid, is
the immediately following instruction from the same cache line.

`consume_count` is the number accepted by issue in the current cycle:

| Value | Effect |
|---:|---|
| `0` | Hold both outputs |
| `1` | Consume only slot 0 |
| `2` | Consume slots 0 and 1 |
| `3` | Illegal; assertion fires and hardware saturates safely |

The frontend intentionally does not combine the last word of one line with the
first word of the next line.  This keeps read-pointer updates atomic.  Normal
sequential fetch begins at word zero, so a full line is still consumed as two
pairs.  A redirect into word 1, 2 or 3 may create one single-issue boundary
cycle.

### Redirect and stale responses

`redirect_valid` has priority over request allocation and instruction
consumption:

1. all queued lines are invalidated;
2. the logical fetch PC becomes `redirect_target`;
3. every accepted old-path request without a response is added to
   `stale_response_count`;
4. old responses are discarded in order;
5. new-path responses are written only after that count reaches zero.

No old-path request is accepted in the redirect cycle.  The target line request
starts on the following cycle.  Redirect targets must be four-byte aligned.

Repeated redirects are supported even while older stale responses are still
outstanding.  This relies on the external interface preserving response order.

## `issue_control`

The selector never skips the oldest instruction.  Let slot 0 be older than
slot 1.

```text
issue0 = backend_ready
         and not kill_issue
         and slot0_valid
         and no RAW against ID/EX or EX/MEM

issue1 = issue0
         and ISSUE_WIDTH == 2
         and slot1_valid
         and both classes are SIMPLE_INT
         and slot1 has no RAW against ID/EX or EX/MEM
         and slot1 does not read slot0.rd
```

`consume_count` is exactly the population count of `issue_valid`.

The pending-destination inputs cover both lanes in ID/EX and EX/MEM.  MEM/WB
is intentionally excluded: the integrated register file must provide bypasses
from both WB write ports to all four ID read ports.

### Dependency rules

- lane0-to-lane1 RAW: serialize; no same-cycle result forwarding;
- WAW: allowed; younger lane 1 wins the final register-file write;
- WAR: allowed;
- dependencies involving `x0`: ignored;
- a slot-1 external RAW consumes slot 0 only and leaves slot 1 at the queue
  head;
- a slot-0 external RAW blocks both slots.

`pair_serialize` records cycles where slot 0 issued but a present slot 1 could
not pair because of class, dependency, or single-issue configuration.

## `execute_lane`

`execute_lane` is purely combinational and can be instantiated for either
integer lane.  It implements:

- ADD, SUB, SLT, SLTU;
- SLL, SRL, SRA;
- XOR, OR, AND;
- all legal RV32I OP-IMM counterparts;
- LUI and AUIPC;
- BRANCH comparisons and target generation;
- JAL and JALR link values and targets.

Only OP, OP-IMM, LUI and AUIPC assert `pairable_simple`.

LOAD/STORE and RV32M are classified and expose accurate source/destination
metadata, but do not assert `supported` or `result_valid`; the integrated full
lane routes them to the existing LSU, multiplier and divider.

The decoder source-use contract is:

| Form | `rs1_used` | `rs2_used` |
|---|---:|---:|
| OP / RV32M | 1 | 1 |
| OP-IMM | 1 | 0 |
| LOAD | 1 | 0 |
| STORE | 1 | 1 |
| BRANCH | 1 | 1 |
| JALR | 1 | 0 |
| JAL / LUI / AUIPC | 0 | 0 |

JALR clears target bit zero as required by the ISA.  Misaligned-instruction
exceptions are outside the current core scope.

## `perf_counters`

All counters are cleared by asynchronous `reset` or synchronous `clear`.
They otherwise wrap naturally at `COUNTER_WIDTH`.

Counters include:

- elapsed cycles;
- issued and retired instruction counts;
- cycles containing two issues or two retires;
- frontend-empty cycles;
- head data-hazard stall cycles;
- memory stall cycles;
- serialized-pair cycles.

Stall causes are independent events and may overlap.  The testbench calculates
IPC from counter deltas; RTL contains no divider.

## Required integration semantics

The eventual pipeline contains two valid bits per stage:

- `id_ex_valid[1:0]`;
- `ex_mem_valid[1:0]`;
- `mem_wb_valid[1:0]`.

Single instructions always occupy lane 0.  A valid lane 1 always implies a
valid, older lane 0.

The integrated design must additionally provide:

1. a four-read/two-write register file with lane-1 write and bypass priority on
   same-address WAW;
2. a single shared data-memory port, with the invariant that an LSU bundle has
   lane 1 invalid;
3. backpressure from a waiting memory operation through all younger stages;
4. two ordered retire records, lane 0 before lane 1;
5. redirect gating by actual stage advancement;
6. EX redirect priority over a younger ID-stage JAL redirect;
7. four NOP words plus the existing fault sideband on an ICache line-fetch
   error.

`ISSUE_WIDTH=1` forces lane 1 inactive while retaining the same frontend,
pipeline and retirement machinery.  It is the required A/B regression mode.

## Assertions and parameter checks

The standalone modules contain non-synthesis checks for:

- 16-byte line size and power-of-two queue depth;
- aligned reset and redirect PCs;
- illegal or unavailable consumption;
- unsolicited or overwriting responses;
- orphan lane-1 issue/retire events;
- dual issue of a serialized class or RAW-dependent pair;
- invalid parameter values;
- inconsistent execution metadata.

Integration should add assertions that lane 1 never carries LSU, MULDIV or
CONTROL; at most one data-memory request exists; redirects only occur when the
source instruction advances; and retire PCs are ordered.

## Minimum acceptance tests

The self-contained test can be built directly from the repository root:

```sh
verilator --binary --timing --sv -Wall -Wno-fatal \
  --top-module dual_issue_core_tb \
  -f test_bench/dual_issue/flist_dual.f
./obj_dir/Vdual_issue_core_tb

verilator --binary --timing --sv -Wall -Wno-fatal \
  --top-module dual_issue_core_tb -GISSUE_WIDTH=1 \
  -f test_bench/dual_issue/flist_dual.f
./obj_dir/Vdual_issue_core_tb
```

Each run contains its own one-cycle ordered instruction-line memory, scalar
data memory, instruction encoders and retirement scoreboard.  It requires no
UVM, DPI, external image or existing testbench finish condition.  The
scoreboard compares lane 0 then lane 1 and checks PC, instruction, commit
valid, destination and data for every retirement record.  Consequently a
correct final register file alone is not enough to pass.

### Full integration acceptance target

The following items remain the acceptance target for the later modification
of the existing pipelined `mycore.v`.  In particular, the single-bundle
standalone core cannot create the EX/MEM redirect-priority cases in items 4
and 6, and its independent testbench intentionally has no DPI connection.

1. Independent ADDI/ADD/logic/shift pairs update architectural state through
   both lanes.
2. lane0-to-lane1 RAW serializes; old-pipeline RAW stalls; WAW permits pairing
   and lane 1 wins; WAR permits pairing; `x0` creates no false dependency.
3. A LOAD, STORE, RV32M or control instruction initially in slot 1 remains at
   the head and executes later in lane 0.
4. Taken/not-taken BRANCH, JAL and JALR are tested at all four line word
   offsets, including redirects during memory backpressure.
5. Old-path line responses after redirect are discarded and no wrong-path
   instruction retires.
6. Same-cycle dual retirement is delivered to the C model in lane0-then-lane1
   order.
7. The existing full regression passes with both `ISSUE_WIDTH=1` and
   `ISSUE_WIDTH=2`, producing identical architectural traces.

### Standalone implemented acceptance

The self-contained test currently verifies:

1. 128 independent ADDI instructions with actual two-lane retirement and the
   performance gates below;
2. lane0-to-lane1 RAW serialization, WAW, WAR, false `x0` dependencies and
   canonical `x0` commit data;
3. every RV32M result form, including divide by zero and `INT_MIN / -1`;
4. signed and unsigned byte/halfword loads, word loads, and
   byte/halfword/word stores through the one-cycle handshake model;
5. reserved LOAD/STORE `funct3` encodings that must not launch a data request;
6. taken and not-taken branches, JAL/JALR links, a redirect coincident with an
   old-path line response, and both register and store wrong-path effects.

The load/store trace detects a retirement pulse repeated while an LSU waits.
The WAW trace requires two ordered commit records and checks the younger
lane-1 value wins the architectural write.  Width-1 and width-2 elaborations
run the same expected traces and print a trace hash for external A/B
comparison.

### Performance gate

For at least 128 independent `SIMPLE_INT` instructions with no external
backpressure, after warm-up:

- dual-issue cycles are at least 80% of issue cycles;
- measured IPC is at least 1.6;
- at least one genuine dual-retire cycle is observed;
- `ISSUE_WIDTH=2` completes in materially fewer cycles than `ISSUE_WIDTH=1`.

Seeing only a nonzero dual-issue counter is not sufficient to mark phase 4 as
complete.
