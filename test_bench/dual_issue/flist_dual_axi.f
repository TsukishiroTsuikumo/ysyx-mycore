+incdir+./dut/axi

dut/mycore/front/fetch_frontend.v
dut/mycore/controller/issue_control.v
dut/mycore/fu/execute_lane.v
dut/mycore/reg/perf_counters.v
dut/mycore/mycore_dual.v

dut/mem/one_set.v
dut/mem/Dcache.v
dut/axi/icache_axi_adapter.v
dut/axi/dcache_axi_adapter.v
dut/axi/axi_read_arbiter.v
dut/axi/axi_addr_decoder.v
dut/axi/axi_error_slave.v
dut/mem/axi_ram_slave.v
dut/axi/cache_axi_memory_system.v

test_bench/wrap/mycore_dual_axi_wrapper.sv
test_bench/dual_issue/dual_axi_smoke_tb.sv
