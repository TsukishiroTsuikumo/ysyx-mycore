# Bounded RV32I/M execution-subset out-of-order experiment

`dut/mycore/ooo/ooo_core.sv` is a standalone phase-5 experiment.  It does not
replace or alter the repository's stable in-order core.  Its purpose is to make
the README roadmap's out-of-order mechanisms executable and independently
testable before they are connected to the cache/AXI integration top.

## Implemented data path

- Two consecutive instructions are fetched, decoded, renamed, dispatched, and
  (when both oldest entries are eligible) committed each cycle.
- A speculative register alias table (RAT), committed RAT, 48-entry physical
  register file, readiness bits, and physical-register free mask remove RAW,
  WAR, and WAW name dependencies.  A lane-1 source sees a lane-0 rename in the
  same packet.
- An eight-entry reorder buffer provides precise, oldest-first retirement.  A
  younger completed result cannot update architectural state until every older
  instruction retires.
- A unified reservation station selects the oldest ready operations.  Two
  simple integer/control lanes may complete in the same cycle.  A separate
  serialized, parameterized-latency unit implements all eight RV32M operations.
- A conservative LSQ records memory operations in program order.  Stores only
  become externally visible at the ROB head.  A load waits for **every** older
  store to retire; this stronger rule covers unresolved store address/data
  hazards without speculative store-to-load forwarding.  A load younger than
  the single unresolved control-flow instruction also waits until that control
  commits, so a wrong-path read cannot reach memory or set the fault diagnostic.
- FENCE has a distinct serialized class.  It dispatches alone, executes only
  at the ROB head, cannot share an execution or commit cycle, and blocks
  younger RS, multiply/divide and LSQ work until it retires.  This gives the
  bounded, single-request memory system an explicit ordering barrier without
  adding a register or memory side effect.
- Branches are predicted not taken.  BEQ/BNE/BLT/BGE/BLTU/BGEU, JAL, and JALR
  calculate their actual next PC out of order.  A mismatch redirects at the ROB
  head, flushes every younger ROB/RS/LSQ/execution entry, restores the RAT from
  the committed RAT (including a JAL/JALR link destination), and reconstructs
  the free mask.  A data response already outstanding when recovery becomes
  necessary is explicitly discarded.
- Two ordered retirement records expose PC, instruction, register-write flag,
  architectural destination, and result for an external reference-model
  scoreboard.

## Deliberate bounds

This is not a complete privileged RISC-V processor and should not be described
as one.

- Documented RV32I integer/control/load-store subset, FENCE, plus RV32M
  arithmetic; no compressed instructions, CSR, FENCE.I/Zifencei, SYSTEM,
  exception, interrupt, privilege, MMU, or atomics.
- Misaligned accesses are outside the contract.  The memory error input sets a
  sticky diagnostic bit; it does not raise an architectural trap.
- Unsupported encodings retire as inert instructions because there is no
  illegal-instruction exception path.
- At most one instruction fetch and one data request are outstanding.
  Instruction and data responses must arrive at least one cycle after request
  acceptance; zero-cycle responses are outside this interface contract.
- At most one unresolved control-flow instruction and one unresolved FENCE may
  be in flight.  Control resolution and recovery happen at the ROB head rather
  than at execute, trading performance for a small and precise recovery
  implementation.
- Control-flow targets are required to be four-byte aligned.  JALR clears bit
  zero, but the experiment has no instruction-address-misaligned exception for
  a remaining bit-one target.
- There is one LSQ address-generation lane, no speculative memory dependence
  predictor, and no store-to-load forwarding.
- The monotonically increasing 32-bit age sequence is not intended for a run
  long enough to wrap.

## Self-checking acceptance test

`flist_ooo.f` builds `test_bench/ooo/ooo_core_tb.sv` together with the DPI-linked
C++ model.  The test is standalone from UVM, but it is no longer a pure
SystemVerilog test.  With Verilator 5.050 and a C++17 compiler, a typical
invocation is:

```sh
verilator --binary -sv -Wall -Wno-fatal \
  --top-module ooo_core_tb \
  -CFLAGS "-std=c++17 -I$(pwd)/C_model" \
  -f flist_ooo.f
./obj_dir/Vooo_core_tb
```

Before DUT execution, the C model independently executes the installed program
and produces the ordered retirement trace, memory-access trace and final
register/memory state.  The testbench compares every retirement record and
accepted data-memory request and then checks all 32 architectural registers and
256 data-memory bytes.  In parallel it exercises:

- a long-latency MUL at the ROB head while independent younger instructions
  complete and the ROB reaches full occupancy;
- inter-packet and same-packet RAW, WAR, and WAW renaming;
- store/load ordering with request backpressure and delayed responses;
- suppression of a faulting wrong-path load behind a taken branch;
- signed and unsigned RV32M multiply/divide/remainder variants;
- x0 invariance, including M/load results whose destination is x0; and
- taken conditional branch, JAL, and JALR recovery with observable wrong-path
  instructions that must never retire;
- a FENCE held behind older work that retires alone and prevents a younger load
  from issuing; and
- a real non-reset ROB transition from nonempty to empty.

An explicit 29-bin semantic gate additionally requires one- and two-wide
dispatch/commit, both ALU lanes and dual execution, M-unit issue/completion,
load/store request and response paths, same-packet dependencies, blocked-head
and ROB-full behavior, conservative LSQ/control blocking, all implemented
recovery forms, younger-state flushing, x0 completion invariants and the
nonempty-to-empty ROB transition. Its blocking local and CI markers are:

```text
OOO_REFERENCE_ORACLE PASS retired=<count> memory=<count>
OOO_COVERAGE status=PASS required=29 hit=29 missing=0
OOO_FENCE_ORDER PASS retired_alone=1 younger_load_blocked=1
OOO_REFERENCE_STATE PASS regs=32 memory_bytes=256 memory_requests=<count>
OOO_CORE_TEST PASS cycles=<count> retired=<count> ooo=<count> rob_full=<count> load_block=<count> recoveries=<count>
```

The roadmap-branch CI requires every marker above; a missing marker or non-zero
test exit fails the job.  The OoO core remains a standalone bounded experiment
and is not integrated into the stable cache/AXI processor top.
