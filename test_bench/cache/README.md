# Direct cache regression

`cache_directed_tb.sv` is a self-checking testbench for the cache controllers at
their CPU and line-memory interfaces. It avoids core and AXI traffic so failures
remain local to `Icache.v`, `Dcache.v`, or `one_set.v`.

Run it with:

```sh
make -C test_bench/cache run
```

The regression checks:

- ICache offsets 0/4/8/12, cold refill, same-line hits, age-based clean
  replacement, reset invalidation, request backpressure, delayed line response,
  and non-allocating `SLVERR`/`DECERR` NOP/fault behavior.
- DCache read/write hits, read refill, write allocate, clean replacement,
  fill-age dirty writeback, refill/writeback backpressure, and
  immediate partial-write RAW behavior.
- DCache `WSTRB` values `0001`, `0010`, `0100`, `1000`, `0011`, `1100`, and
  `1111`; cross-line reads at byte offsets 13, 14, and 15; read and writeback
  `SLVERR`/`DECERR`; and retention of a dirty line after failed writeback.

Thirty-six named semantic bins form an internal required-bin bitmap. The test
terminates fatally if any required bin is missing. The coverage marker is:

```text
CACHE_COVERAGE status=PASS required=36 hit=36 missing=0
```

The acceptance marker is:

```text
CACHE_DIRECTED_ACCEPTANCE status=PASS
```

Current RTL limitations are reflected rather than hidden: ICache has no
explicit flush input (reset invalidates its contents), aligned instruction
fetches are checked at both sides of a line boundary, and DCache cross-line
writes are outside the implemented controller contract. Replacement is
described as fill-age/age-based because cache hits do not update
`one_set.v`'s age counters.
