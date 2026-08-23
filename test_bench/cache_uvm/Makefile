SHELL := /bin/bash

VERILATOR ?= verilator
UVM_HOME  ?= ../../.ci/uvm-core
OBJ_DIR   ?= obj_dir_cache_uvm
LOG       ?= log/cache-uvm.log
VERILATOR_JOBS ?= 4

.PHONY: build run run-only clean

build:
	cd ../.. && $(VERILATOR) --binary --timing -sv -Wall -Wno-fatal --assert \
		-j $(VERILATOR_JOBS) \
		--output-groups 24 --output-split 0 --output-split-cfuncs 0 \
		--top-module cache_uvm_tb \
		--Mdir test_bench/cache_uvm/$(OBJ_DIR) \
		-CFLAGS "-std=c++20 -O0" \
		-I"$(abspath $(UVM_HOME))/src" +incdir+"$(abspath $(UVM_HOME))/src" \
		"$(abspath $(UVM_HOME))/src/uvm_pkg.sv" \
		-f test_bench/cache_uvm/flist_cache_uvm.f +define+UVM_NO_DPI

run: build run-only

run-only:
	mkdir -p $(dir $(LOG))
	set -o pipefail; ./$(OBJ_DIR)/Vcache_uvm_tb \
		+UVM_TESTNAME=cache_uvm_test 2>&1 | tee $(LOG)
	grep -Fq 'CACHE_UVM_COVERAGE status=PASS required=29 hit=29 missing=0' $(LOG)
	grep -Fq 'CACHE_UVM_ORDER status=PASS' $(LOG)
	grep -Fq 'CACHE_UVM_TEST status=PASS transactions=54 checks=32 reads=32 writes=19 controls=3 uvm_errors=0' $(LOG)
	! grep -Eq 'UVM_(ERROR|FATAL)[[:space:]]*:[[:space:]]*[1-9]' $(LOG)

clean:
	rm -rf $(OBJ_DIR) log
