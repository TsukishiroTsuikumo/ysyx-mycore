TB_TOP    			:= test_bench
OBJ_DIR   			:= obj_dir
VERILATOR 			:= verilator
TEST 				?= program_test
RUN_ARGS 			?= +UVM_TESTNAME=$(TEST)
VERILATOR_SOLVER 	= z3 --in
export VERILATOR_SOLVER

ifeq ($(USE_CACHE),1)
RUN_ARGS += +USE_CACHE
endif
ifneq ($(MEM_FILE),)
RUN_ARGS += +MEM_FILE=$(MEM_FILE)
endif
ifneq ($(TARGET_COMMITS),)
RUN_ARGS += +TARGET_COMMITS=$(TARGET_COMMITS)
endif
ifneq ($(TIMEOUT_CYCLES),)
RUN_ARGS += +TIMEOUT_CYCLES=$(TIMEOUT_CYCLES)
endif
ifneq ($(SIM_TIMEOUT),)
RUN_ARGS += +SIM_TIMEOUT=$(SIM_TIMEOUT)
endif

CXX 				?= g++
C_MODEL_DIR 		:= C_model
C_MODEL_BIN 		:= $(C_MODEL_DIR)/cmodel
C_MODEL_SRCS 		:= $(C_MODEL_DIR)/main.cpp $(C_MODEL_DIR)/model.cpp $(C_MODEL_DIR)/state.cpp
C_MODEL_DPI_SRCS 	:= $(C_MODEL_DIR)/model.cpp $(C_MODEL_DIR)/state.cpp $(C_MODEL_DIR)/cmodel_dpi.cpp
C_MODEL_FLAGS 		:= -std=c++17 -Wall -Wextra -I $(C_MODEL_DIR)

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
	-CFLAGS "-std=c++17 -I$(C_MODEL_DIR)" \
	$(UVM_HOME)/src/uvm_pkg.sv \
	-F flist.f \
	$(C_MODEL_DPI_SRCS) \
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
	rm -rf $(OBJ_DIR) *.vcd *.fst *.log $(C_MODEL_BIN)

cmodel:
	$(CXX) $(C_MODEL_FLAGS) $(C_MODEL_SRCS) -o $(C_MODEL_BIN)

image:
	riscv64-unknown-elf-gcc ./scripts/start.S \
		./csrc/main.cpp \
		-march=rv32im -mabi=ilp32 \
		-nostdlib -nostartfiles -ffreestanding \
		-Wl,-T,./scripts/linker.ld \
		-o test.elf
	riscv64-unknown-elf-objcopy -O binary test.elf test.bin
	xxd -e -g 4 -c 4 test.bin | awk '{print $$2}' > image.mem
	rm -f test.elf test.bin

.PHONY: build run clean image cmodel
