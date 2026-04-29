TOP       := test_bench
OBJ_DIR   := obj_dir
VERILATOR := verilator

VERILATOR_FLAGS = \
	-sv \
	--timing \
	--binary \
	--build -j 0 \
	-Wall -Wno-fatal \
	--top-module $(TOP) \
	-I$(UVM_HOME)/src \
	+incdir+$(UVM_HOME)/src \
	+define+UVM_NO_DPI \
	-F filst.f

all: build
	./$(OBJ_DIR)/V$(TOP)

build:
	$(VERILATOR) $(VERILATOR_FLAGS) \
		$(UVM_HOME)/src/uvm_pkg.sv


clean:
	rm -rf $(OBJ_DIR) *.vcd *.fst

.PHONY: all build run clean

