# AXI verification

The package now provides both active and passive AXI4 components:

- `axi_sequencer`, `axi_driver`, and `axi_agent` for master traffic;
- `axi_monitor`, `axi_coverage`, and `axi_observer` for passive observation;
- `axi_master_sequence` and `axi_master_test` as an executable active-agent
  smoke test.

The active driver can transmit FIXED/INCR/WRAP metadata and arbitrary burst
lengths represented by the transaction payload queues, together with byte
strobes, USER and owner sidebands, response capture, and programmable address,
W-beat, and B/R-ready delays. The executable smoke validates only aligned,
full-width, four-beat INCR lines, matching the current RTL subset; the other
metadata forms are not yet acceptance-tested. The driver intentionally allows
one outstanding sequence item at a time, so multi-ID out-of-order generation
is deferred to later stress tests.

## Active master smoke

`axi_master_uvm_tb.sv` connects an active 32-bit AXI agent to the deterministic
backpressured `axi_random_slave`. The test performs an instruction-owner line
read, a data-owner line write, and a data-owner readback. The agent's monitor is
connected to the existing coverage subscriber, and the protocol checker is
enabled with final-quiescence checking.

With `UVM_HOME` pointing at Accellera UVM 2020.3.1, build and run it from the
repository root:

```sh
verilator --binary --timing -sv -Wall -Wno-fatal --assert \
  --top-module axi_master_uvm_tb --Mdir obj_dir_axi_uvm \
  -I"$UVM_HOME/src" +incdir+"$UVM_HOME/src" \
  "$UVM_HOME/src/uvm_pkg.sv" \
  -f test_bench/axi/flist_axi_master_uvm.f +define+UVM_NO_DPI
./obj_dir_axi_uvm/Vaxi_master_uvm_tb +UVM_TESTNAME=axi_master_test
```

A successful run prints `AXI_ACTIVE_UVM_TEST ... PASS`, an
`AXI_ACCEPTANCE ... status=PASS` report, and an AXI protocol report with zero
procedural errors and no pending transactions.

## Passive core observation

The passive monitor, coverage subscriber, and protocol checker are connected to
the current core testbench. `test_bench/test_bench.sv` taps the shared bus inside
`dut.u_mem` at these boundaries:

- DCache write channels: `dc_axi_*`
- post-arbitration I/D read channels: `arb_axi_*`

The tap drives `shared_axi_if_inst` and does not modify synthesizable RTL. The
testbench ties REGION/USER to zero and derives the verification-only owner field
from the fixed ICache/DCache AXI IDs.

`flist.f` compiles the files in this order:

1. `uvm_pkg.sv`
2. `test_bench/interface/axi_if.sv`
3. `test_bench/axi/axi_verif_pkg.sv`
4. `test_bench/assertions/axi_protocol_checker.sv`
5. `mycore_pkg.sv` and the normal test top

`program_test_env` enables an automatic cache-line acceptance gate. A successful
run reports both:

```text
AXI_ACCEPTANCE status=PASS ...
AXI_PROTOCOL_REPORT: AW=... W=... B=... AR=... R=...
```

The acceptance gate requires at least one completed successful read, four-beat
32-bit INCR line traffic, correct LAST/beat counts, OKAY responses, and the
fixed owner/ID mapping. Violations are UVM errors and therefore fail regression.

Program tests may stop while the frontend has a legal speculative fetch in
flight, so end-of-test quiescence is informational by default. Dedicated AXI
tests can set `require_quiescent_end` on the observer and instantiate the
checker with `CHECK_FINAL_QUIESCENCE=1`.

Add `test_bench` and the UVM source directory to the compiler include path when
using the components from another top.

Instantiate `axi_if` with the intended bus widths. The current AXI RTL defaults
to a 2-bit ID and uses an active-high `reset`, so a standalone top should use
the matching ID width and connect `axi_bus.aresetn = ~reset`. Drive `aw_owner`
and `ar_owner` with `axi_if.OWNER_INSTR` or `axi_if.OWNER_DATA`; these are
verification sidebands and are not part of AXI4. Instantiate or bind an
`axi_protocol_checker` to the interface.

At a shared downstream interface, derive owner from the arbiter selection (or
from the reserved I-cache/D-cache IDs) and hold it with the address payload
until the `VALID && READY` handshake.

The initial RTL adapters do not expose AXI `REGION` or `USER` ports. A bridge
in the standalone top should tie the corresponding interface fields to zero.

For another UVM environment, the packaged active agent or passive observer can
be instantiated using the same width parameters as the interface:

```systemverilog
typedef virtual axi_if #(32, 32, 2, 1, 1) axi_vif_t;
typedef axi_agent #(32, 32, 2, 1, 1) axi_agent_t;
typedef axi_observer #(32, 32, 2, 1, 1) axi_observer_t;
axi_agent_t axi_agent;
axi_observer_t axi_obs;

uvm_config_db#(uvm_active_passive_enum)::set(
    this, "axi_agent", "is_active", UVM_ACTIVE);
uvm_config_db#(axi_vif_t)::set(this, "axi_*", "vif", axi_bus);
axi_agent = axi_agent_t::type_id::create("axi_agent", this);
axi_obs = axi_observer_t::type_id::create("axi_obs", this);
```

The coverage subscriber uses explicit semantic counters for portability. Set
these optional `uvm_config_db#(bit)` keys on the subscriber to turn bins into
regression gates:

- `require_backpressure_coverage`: requires AW/W/B/AR/R backpressure hits.
- `require_owner_coverage`: requires instruction reads, data reads, and data
  writes.
- `require_last_error_coverage`: intended only for negative tests; requires
  malformed read and write LAST observations.
- `require_cache_line_traffic`: enables the automatic four-beat/OKAY/owner-ID
  acceptance gate used by `program_test_env`.

For Verilator, enable `--assert` so the SVA checker is active.
