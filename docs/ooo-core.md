# Bounded RV32IM out-of-order experiment

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
  hazards without speculative store-to-load forwarding.
- Branches are predicted not taken.  BEQ/BNE/BLT/BGE/BLTU/BGEU, JAL, and JALR
  calculate their actual next PC out of order.  A mismatch redirects at the ROB
  head, flushes every younger ROB/RS/LSQ/execution entry, restores the RAT from
  the committed RAT (including a JAL/JALR link destination), and reconstructs
  the free mask.  An outstanding wrong-path load response is explicitly
  discarded.
- Two ordered retirement records expose PC, instruction, register-write flag,
  architectural destination, and result for an external reference-model
  scoreboard.

## Deliberate bounds

This is not a complete privileged RISC-V processor and should not be described
as one.

- RV32IM user instructions only; no compressed instructions, CSR, fence,
  exception, interrupt, privilege, MMU, or atomics.
- Misaligned accesses are outside the contract.  The memory error input sets a
  sticky diagnostic bit; it does not raise an architectural trap.
- Unsupported encodings retire as inert instructions because there is no
  illegal-instruction exception path.
- At most one instruction fetch and one data request are outstanding.  A data
  response must arrive at least one cycle after request acceptance.
- Only one unresolved control-flow instruction may be in flight.  Resolution
  and recovery happen at the ROB head rather than at execute, trading
  performance for a small and precise recovery implementation.
- There is one LSQ address-generation lane, no speculative memory dependence
  predictor, and no store-to-load forwarding.
- The monotonically increasing 32-bit age sequence is not intended for a run
  long enough to wrap.

## Self-checking acceptance test

`flist_ooo.f` builds `test_bench/ooo/ooo_core_tb.sv` as a pure SystemVerilog
test.  With Verilator 5.050, a typical invocation is:

```sh
verilator --binary -sv -Wall -Wno-fatal --top-module ooo_core_tb -f flist_ooo.f
./obj_dir/Vooo_core_tb
```

The test checks an ordered reference trace and final architectural state while
exercising:

- a long-latency MUL at the ROB head while independent younger instructions
  complete and the ROB reaches full occupancy;
- inter-packet and same-packet RAW, WAR, and WAW renaming;
- store/load ordering with request backpressure and delayed responses;
- signed and unsigned RV32M multiply/divide/remainder variants;
- x0 invariance; and
- taken conditional branch, JAL, and JALR recovery with observable wrong-path
  instructions that must never retire.

Success is reported exactly as `OOO_CORE_TEST PASS` followed by diagnostic
counters.
