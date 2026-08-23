# Active Cache UVM Regression

This testbench drives the real `Icache` and `Dcache` RTL through an active
UVM agent.  It is separate from the procedural directed-cache gate: requests
come from a sequence/driver, completions are reconstructed by a monitor, and
an independent scoreboard checks response data and per-cache request order.
A UVM line-memory component supplies deterministic pseudo-random ready stalls
and response latency while servicing the I-cache and D-cache channels in
parallel.

## Running

Accellera UVM 2020.3.1, Verilator 5.050 or newer, and a C++20-capable host
compiler are required. From the repository root:

```sh
make -C test_bench/cache_uvm run UVM_HOME=/absolute/path/to/uvm-core
```

The default build uses 24 Verilator output groups and four compiler jobs to
keep the UVM build bounded.  `VERILATOR_JOBS` can be reduced on smaller
machines.  Generated objects and the log stay below
`test_bench/cache_uvm/obj_dir_cache_uvm` and
`test_bench/cache_uvm/log/cache-uvm.log`; both paths are ignored by Git.

## Acceptance contract

The regression completes 54 monitored transactions and 32 independent read
checks.  Its 29 required semantic points cover:

- I-cache miss, resident hit, consecutive misses, same-set clean replacement,
  explicit flush invalidation/refill, an accepted in-flight miss flushed and
  drained without exposing its stale `SLVERR` or data before a fresh refill,
  reset invalidation/refill, and repeated non-allocating `SLVERR`/`DECERR`
  responses;
- D-cache read/write hit and miss, write allocation, immediate RAW readback,
  all supported byte/halfword/word/zero write-strobe classes, dirty eviction,
  successful writeback/refetch, refill error non-allocation, failed dirty
  writeback with resident-line retention, and a supported cross-line read;
- zero/mid/long response delays, request-channel backpressure, consecutive
  misses, and a true interval in which I-cache and D-cache line reads are both
  outstanding.

Success is machine-checkable through these exact marker prefixes:

```text
CACHE_UVM_COVERAGE status=PASS required=29 hit=29 missing=0
CACHE_UVM_ORDER status=PASS
CACHE_UVM_TEST status=PASS transactions=54 checks=32 reads=32 writes=19 controls=3 uvm_errors=0
```

The GitHub Actions gate also rejects any non-zero `UVM_ERROR` or `UVM_FATAL`
summary.

## RTL boundary

`Icache.flush` is a real controller input and this regression proves that it
invalidates a resident line, drains an already accepted line request without
leaking its response, and permits a refill only after drain. The current CPU pipeline does
not yet issue that input from `FENCE.I`; non-UVM instances explicitly tie it
low.  The cache-line response contract is a one-cycle valid pulse after (and
never on) the accepting request edge; the zero-delay bin means the shortest
legal post-handshake response, not a combinational response.  D-cache
cross-line reads are supported and checked.  A single CPU write
request is not split across two cache lines by the current RTL, so cross-line
writes are intentionally outside this gate.
