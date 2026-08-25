`ifndef YSYX_CACHE_UVM_PKG_SV
`define YSYX_CACHE_UVM_PKG_SV
`timescale 1ns/1ps

package cache_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    `include "cache_transaction.svh"
    `include "cache_sequencer.svh"
    `include "cache_driver.svh"
    `include "cache_monitor.svh"
    `include "cache_agent.svh"
    `include "cache_memory_model.svh"
    `include "cache_scoreboard.svh"
    `include "cache_sequence.svh"
    `include "cache_test.svh"
endpackage

`endif
