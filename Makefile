SHELL               := /bin/bash

TB_TOP    			:= test_bench
OBJ_DIR   			:= obj_dir
VERILATOR 			:= verilator
DUT_TOP             ?= mycore_system
DUT_FILELIST        ?= flist_rtl.f
TEST 				?= program_test
RUN_ARGS 			?= +UVM_TESTNAME=$(TEST)
VERILATOR_SOLVER 	= z3 --in
export VERILATOR_SOLVER
VERILATOR_FLAGS 	= \
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
ifeq ($(REQUIRE_ISA_COVERAGE),1)
RUN_ARGS += +REQUIRE_ISA_COVERAGE
endif

IMAGE_DIR 			?= ./csrc/image
IMAGE_TARGET 		?= main_image.mem

# Only capture extra args when 'image' is the target
ifneq ($(filter image,$(MAKECMDGOALS)),)
IMAGE_ARGS 			:= $(filter-out image,$(MAKECMDGOALS))
ifeq ($(strip $(IMAGE_ARGS)),)
IMAGE_SRC 			:= ./csrc/main.cpp
else
IMAGE_SRC 			:= $(IMAGE_ARGS)
endif
$(IMAGE_ARGS):;
endif

CXX 				?= g++
C_MODEL_DIR 		:= C_model
C_MODEL_BIN 		:= $(C_MODEL_DIR)/cmodel
C_MODEL_SRCS 		:= $(C_MODEL_DIR)/main.cpp $(C_MODEL_DIR)/model.cpp $(C_MODEL_DIR)/state.cpp
C_MODEL_DPI_SRCS 	:= $(C_MODEL_DIR)/model.cpp $(C_MODEL_DIR)/state.cpp $(C_MODEL_DIR)/cmodel_dpi.cpp
C_MODEL_FLAGS 		:= -std=c++17 -Wall -Wextra -I $(C_MODEL_DIR)

LOG ?=
COVERAGE ?= 0
COVERAGE_FILE ?= $(OBJ_DIR)/coverage.dat

ifeq ($(COVERAGE),1)
VERILATOR_FLAGS += --coverage-line --coverage-toggle
RUN_ARGS += +verilator+coverage+file+$(COVERAGE_FILE)
endif



run: build run-only

run-only:
	set -o pipefail; VERILATOR_SOLVER="$(VERILATOR_SOLVER)" ./$(OBJ_DIR)/V$(TB_TOP) $(RUN_ARGS) 2>&1 $(if $(LOG),| tee $(LOG))

build:
	$(VERILATOR) $(VERILATOR_FLAGS)

dut-syntax:
	python3 scripts/check_dut_verilog.py

lint-dut: dut-syntax
	$(VERILATOR) --lint-only --language 1364-2005 --timing \
		-Wall -Wno-fatal --top-module $(DUT_TOP) -f $(DUT_FILELIST)

checkv: lint-dut

checksv:
	rm -f flistsv.f
	find . -name "*.sv" > flistsv.f
	$(VERILATOR) -sv --lint-only -Wall -f flistsv.f

axi-test:
	$(VERILATOR) --binary --timing -sv -Wall -Wno-fatal \
		--top-module axi_subsystem_tb --Mdir obj_dir_axi -f flist_axi_tb.f
	./obj_dir_axi/Vaxi_subsystem_tb

cache-test:
	$(MAKE) -C test_bench/cache run

cache-uvm-test:
	$(MAKE) -C test_bench/cache_uvm run

dual-test:
	$(VERILATOR) --binary --timing -sv -Wall -Wno-fatal --assert -j 0 \
		--top-module dual_issue_core_tb --Mdir obj_dir_dual \
		-f test_bench/dual_issue/flist_dual.f
	./obj_dir_dual/Vdual_issue_core_tb

dual-system-test:
	$(VERILATOR) --binary --timing -sv -Wall -Wno-fatal --assert -j 0 \
		--top-module dual_system_tb --Mdir obj_dir_dual_system \
		-f test_bench/dual_issue/flist_dual_system.f
	./obj_dir_dual_system/Vdual_system_tb

ooo-test:
	$(VERILATOR) --binary --timing -sv -Wall -Wno-fatal --assert -j 0 \
		--top-module ooo_core_tb --Mdir obj_dir_ooo \
		-f test_bench/ooo/flist_ooo.f
	./obj_dir_ooo/Vooo_core_tb

ooo-system-test:
	$(VERILATOR) --binary --timing -sv -Wall -Wno-fatal --assert -j 0 \
		--top-module ooo_system_tb --Mdir obj_dir_ooo_system \
		-f test_bench/ooo/flist_ooo_system.f
	./obj_dir_ooo_system/Vooo_system_tb

ooo-rat-test:
	$(VERILATOR) --binary --timing -sv -Wall -Wno-fatal --assert -j 0 \
		--top-module ooo_rat_tb --Mdir obj_dir_ooo_rat \
		-f test_bench/ooo/flist_ooo_rat.f
	./obj_dir_ooo_rat/Vooo_rat_tb

ooo-rob-rs-test:
	$(VERILATOR) --binary --timing -sv -Wall -Wno-fatal --assert -j 0 \
		--top-module ooo_rob_rs_tb --Mdir obj_dir_ooo_rob_rs \
		-f test_bench/ooo/flist_ooo_rob_rs.f
	./obj_dir_ooo_rob_rs/Vooo_rob_rs_tb

ooo-lsq-exec-test:
	$(VERILATOR) --binary --timing -sv -Wall -Wno-fatal --assert -j 0 \
		--top-module ooo_lsq_exec_tb --Mdir obj_dir_ooo_lsq_exec \
		-f test_bench/ooo/flist_ooo_lsq_exec.f
	./obj_dir_ooo_lsq_exec/Vooo_lsq_exec_tb

ooo-unit-test: ooo-rat-test ooo-rob-rs-test ooo-lsq-exec-test

clean:
	rm -rf $(OBJ_DIR) obj_dir_dual obj_dir_dual_system \
		obj_dir_ooo obj_dir_ooo_system obj_dir_ooo_rat \
		obj_dir_ooo_rob_rs obj_dir_ooo_lsq_exec coverage \
		*.vcd *.fst *.log $(C_MODEL_BIN) $(C_MODEL_DIR)/cmodel_tests

cmodel:
	$(CXX) $(C_MODEL_FLAGS) $(C_MODEL_SRCS) -o $(C_MODEL_BIN)

cmodel-test:
	$(CXX) $(C_MODEL_FLAGS) C_model/model.cpp C_model/state.cpp C_model/tests.cpp -o $(C_MODEL_DIR)/cmodel_tests
	./$(C_MODEL_DIR)/cmodel_tests

regression:
	python3 scripts/regression.py

coverage:
	python3 scripts/regression.py --coverage
	verilator_coverage --write-info $(OBJ_DIR)/coverage.info coverage/*.dat

image:
	mkdir -p $(IMAGE_DIR)
	riscv64-unknown-elf-gcc \
		./scripts/start.S \
		$(IMAGE_SRC) \
		-march=rv32im -mabi=ilp32 \
		-nostdlib -nostartfiles -ffreestanding \
		-Wl,-T,./scripts/linker.ld \
		-o $(IMAGE_DIR)/test.elf
	riscv64-unknown-elf-objcopy -O binary $(IMAGE_DIR)/test.elf $(IMAGE_DIR)/test.bin
	mkdir -p $(IMAGE_DIR)/$(dir $(IMAGE_TARGET))
	xxd -e -g 4 -c 4 $(IMAGE_DIR)/test.bin | awk '{print $$2}' > $(IMAGE_DIR)/$(IMAGE_TARGET)
	rm -f $(IMAGE_DIR)/test.elf $(IMAGE_DIR)/test.bin

.PHONY: build run run-only clean image cmodel cmodel-test regression coverage \
	dut-syntax lint-dut checkv checksv axi-test cache-test cache-uvm-test \
	dual-test dual-system-test ooo-test ooo-system-test ooo-rat-test \
	ooo-rob-rs-test ooo-lsq-exec-test ooo-unit-test
