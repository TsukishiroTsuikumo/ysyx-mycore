TB_TOP    			:= test_bench
OBJ_DIR   			:= obj_dir
VERILATOR 			:= verilator
TEST 				?= mycore_test
RUN_ARGS 			?= +UVM_TESTNAME=$(TEST)
VERILATOR_SOLVER 	= z3 --in
export VERILATOR_SOLVER

VERILATOR_FLAGS = \
	-sv \
	--timing \
	--binary \
	--trace \
	--build -j 0 \
	-Wall -Wno-fatal \
	--top-module $(TB_TOP) \
	-I$(UVM_HOME)/src \
	+incdir+$(UVM_HOME)/src \
	+incdir+./test_bench \
	$(UVM_HOME)/src/uvm_pkg.sv \
	-F flist.f \
	+define+UVM_NO_DPI

run: build
	VERILATOR_SOLVER="$(VERILATOR_SOLVER)" ./$(OBJ_DIR)/V$(TB_TOP) $(RUN_ARGS)

build:
	$(VERILATOR) $(VERILATOR_FLAGS)

checkv:
	rm -f flistv.f
	find . -name "*.v" > flistv.f
	$(VERILATOR) --lint-only -Wall -f flistv.f

checksv:
	rm -f flistsv.f
	find . -name "*.sv" > flistsv.f
	$(VERILATOR) -sv --lint-only -Wall -f flistsv.f

clean:
	rm -rf $(OBJ_DIR) *.vcd *.fst *.log

.PHONY: build run clean
