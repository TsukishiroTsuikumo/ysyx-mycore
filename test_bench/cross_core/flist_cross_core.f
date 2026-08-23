--assert
--timing
+incdir+./test_bench

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

dut/mycore/front/fetch_frontend.v
dut/mycore/controller/issue_control.v
dut/mycore/fu/execute_lane.v
dut/mycore/reg/perf_counters.v
dut/mycore/mycore_dual.v

dut/mycore/ooo/ooo_decode.sv
dut/mycore/ooo/ooo_core.sv

test_bench/cross_core/cross_core_equivalence_tb.sv
C_model/model.cpp
C_model/state.cpp
C_model/cmodel_dpi.cpp
