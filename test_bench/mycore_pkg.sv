`ifndef MYCORE_PKG_SV
`define MYCORE_PKG_SV
`timescale 1ns/1ps

package mycore_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "test_bench/seq/mycore_item.svh"
  `include "test_bench/seq/mycore_sequence.svh"

  `include "test_bench/agent/mycore_sequencer.svh"
  `include "test_bench/agent/mycore_driver.svh"
  `include "test_bench/agent/mycore_monitor.svh"

  `include "test_bench/env/mycore_agent_config.svh"
  `include "test_bench/env/mycore_agent.svh"
  `include "test_bench/env/mycore_scoreboard.svh"
  `include "test_bench/env/mycore_env.svh"

  `include "test_bench/test/mycore_test.svh"

  `include "r_type_test/r_type_item.svh"
  `include "r_type_test/r_type_scoreboard.svh"
  `include "r_type_test/r_type_test.svh"

  `include "program_test/program_item.svh"
  `include "program_test/program_monitor.svh"
  `include "program_test/program_scoreboard.svh"
  `include "program_test/program_test.svh"

endpackage

`endif
