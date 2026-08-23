`ifndef YSYX_AXI_VERIF_PKG_SV
`define YSYX_AXI_VERIF_PKG_SV

`timescale 1ns/1ps

// Compile after uvm_pkg.sv and test_bench/interface/axi_if.sv.  A future
// standalone AXI top only needs to import axi_verif_pkg and place the monitor
// and coverage subscriber in its environment.
package axi_verif_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "axi/axi_transaction.svh"
    `include "axi/axi_monitor.svh"
    `include "axi/axi_coverage.svh"
    `include "axi/axi_observer.svh"

endpackage

`endif
