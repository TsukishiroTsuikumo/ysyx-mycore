SHELL := /bin/bash

VERILATOR ?= verilator
TOP       := cache_directed_tb
OBJ_DIR   := obj_dir
LOG       := cache_directed.log

VERILATOR_FLAGS := \
	-sv \
	--timing \
	--binary \
	--build -j 0 \
	--output-split-cfuncs 0 \
	-Wall -Wno-fatal \
	--top-module $(TOP) \
	--Mdir $(OBJ_DIR) \
	-F flist_cache_directed.f

.PHONY: build run clean

build:
	$(VERILATOR) $(VERILATOR_FLAGS)

run: build
	set -o pipefail; ./$(OBJ_DIR)/V$(TOP) 2>&1 | tee $(LOG)
	grep -q "ICACHE_DIRECTED_TEST: PASS" $(LOG)
	grep -q "DCACHE_DIRECTED_TEST: PASS" $(LOG)
	grep -q "CACHE_COVERAGE status=PASS required=36 hit=36 missing=0" $(LOG)
	grep -q "CACHE_DIRECTED_ACCEPTANCE status=PASS" $(LOG)

clean:
	rm -rf $(OBJ_DIR) $(LOG)
