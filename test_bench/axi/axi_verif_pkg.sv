`ifndef YSYX_AXI_VERIF_PKG_SV
`define YSYX_AXI_VERIF_PKG_SV

`timescale 1ns/1ps

// Compile after uvm_pkg.sv and test_bench/interface/axi_if.sv.  The package
// contains both the passive observer used by the core environment and a
// reusable active master agent with an executable smoke sequence/test.
package axi_verif_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "axi/axi_transaction.svh"
    `include "axi/axi_sequencer.svh"
    `include "axi/axi_driver.svh"
    `include "axi/axi_monitor.svh"
    `include "axi/axi_coverage.svh"
    `include "axi/axi_agent.svh"
    `include "axi/axi_master_sequence.svh"
    `include "axi/axi_master_test.svh"
    `include "axi/axi_observer.svh"

endpackage

`endif
