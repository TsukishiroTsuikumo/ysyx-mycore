+incdir+./dut/axi

dut/mycore/mycore.v
dut/mycore/reg/reg_PC.v
dut/mycore/reg/reg_R.v
dut/mycore/reg/instr_queue.v
dut/mycore/controller/decoder.v
dut/mycore/controller/controller.v
dut/mycore/controller/hazard.v
dut/mycore/fu/shifter.v
dut/mycore/fu/multiplier.v
dut/mycore/fu/alu.v
dut/mycore/fu/lsu.v
dut/mycore/fu/adder.v
dut/mycore/fu/divider.v
dut/mycore/fu/imu.v

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

test_bench/wrap/mycore_wrapper.sv
