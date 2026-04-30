`ifndef MYCORE_PKG_SV
`define MYCORE_PKG_SV
`timescale 1ns/1ps

package mycore_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "seq/sequence_item.sv"
  `include "seq/sequence.sv"

  `include "agent/sequencer.sv"
  `include "agent/driver.sv"
  `include "agent/monitor.sv"

  `include "env/agent.sv"
  //`include "env/scoreboard.sv"
  `include "env/env.sv"

  `include "test/mycore_test.sv"

endpackage

`endif