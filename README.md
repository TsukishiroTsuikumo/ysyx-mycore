# ysyx-mycore

`ysyx-mycore` is a RISC-V CPU and verification project built around an RV32IM processor core and a SystemVerilog/UVM-based verification environment.

## Current Components

- RISCV processor core
  - Single-issue in-order pipeline
  - RV32IM instruction support
  - Frontend instruction queue for decoupling instruction fetch from backend execution
  - Basic hazard, stall, valid, and flush control

- Cache and memory subsystem
  - ICache prototype
  - DCache prototype
  - Unified memory model
  - Cache-line based refill/write-back interface

- UVM verification framework
  - Reusable UVM testbench structure
  - Instruction-level random tests
  - Program-level verification
  - Factory override support for building specialized sub-tests

## Planned Work

- Add AXI-based interconnect
  - Connect ICache, DCache, memory, and future SoC peripherals through AXI
  - Add AXI read/write adapters

- Upgrade the processor microarchitecture
  - Explore multi-issue execution
  - Gradually migrate from an in-order pipeline to an out-of-order core

- Extend the UVM verification environment
  - Add test for CPU peripheral modules, including cache, memory and AXI subsystems
  - Add line coverage and functional coverage
  - Integrate a software reference model for result checking
