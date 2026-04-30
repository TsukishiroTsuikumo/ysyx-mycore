TB_TOP    := test_bench
OBJ_DIR   := obj_dir
VERILATOR := verilator

VERILATOR_FLAGS = \
	-sv \
	--timing \
	--binary \
	--build -j 0 \
	-Wall -Wno-fatal \
	--top-module $(TB_TOP) \
	-I$(UVM_HOME)/src \
	+incdir+$(UVM_HOME)/src \
	+define+UVM_NO_DPI \
	-F filst.f

run: build
	./$(OBJ_DIR)/V$(TB_TOP)

build:
	rm -f flist.f
	find . -name "*.v" > flist.f
	find . -name "*.sv" >> flist.f
	$(VERILATOR) $(VERILATOR_FLAGS) \
	$(UVM_HOME)/src/uvm_pkg.sv

checkv:
	rm -f flistv.f
	find . -name "*.v" > flistv.f
	$(VERILATOR) --lint-only -Wall -f flistv.f

checksv:
	rm -f flistsv.f
	find . -name "*.sv" > flistsv.f
	$(VERILATOR) -sv --lint-only -Wall -f flistsv.f

clean:
	rm -rf $(OBJ_DIR) *.vcd *.fst

.PHONY: build run clean

