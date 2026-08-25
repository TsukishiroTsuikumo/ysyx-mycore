--assert
+incdir+./dut/axi
+incdir+./test_bench

dut/mycore/mycore.v
dut/mycore/reg/reg_PC.v
dut/mycore/reg/reg_R.v
dut/mycore/reg/instr_queue.v
dut/mycore/reg/rat.v
dut/mycore/reg/rob.v
dut/mycore/reg/reservation_station.v
dut/mycore/reg/lsq.v
dut/mycore/controller/decoder.v
dut/mycore/controller/controller.v
dut/mycore/controller/hazard.v
dut/mycore/controller/muldiv_tracker.v
dut/mycore/controller/cdb_arbiter.v
dut/mycore/fu/shifter.v
dut/mycore/fu/multiplier.v
dut/mycore/fu/alu.v
dut/mycore/fu/lsu.v
dut/mycore/fu/adder.v
dut/mycore/fu/divider.v
dut/mycore/fu/imu.v
dut/mycore/fu/load_extender.v

dut/mem/one_set.v
dut/mem/Icache.v
dut/mem/Dcache.v

dut/axi/icache_axi_adapter.v
dut/axi/dcache_axi_adapter.v
dut/axi/axi_read_arbiter.v
dut/axi/axi_addr_decoder.v
dut/axi/axi_error_slave.v
dut/mem/axi_ram_slave.v
dut/axi/cache_axi_memory_system.v
dut/mycore_system.v

test_bench/interface/icache_if.sv
test_bench/interface/dcache_if.sv
test_bench/interface/probe_if.sv
test_bench/interface/axi_if.sv

test_bench/wrap/mycore_wrapper.sv
test_bench/axi/axi_verif_pkg.sv
test_bench/assertions/axi_protocol_checker.sv
test_bench/mycore_pkg.sv
test_bench/test_bench.sv
