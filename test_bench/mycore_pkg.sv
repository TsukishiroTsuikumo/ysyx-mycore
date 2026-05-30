`ifndef NEW_MYCORE_PKG_SV
`define NEW_MYCORE_PKG_SV
`timescale 1ns/1ps

package mycore_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `ifndef TEST_TIMES
        `define TEST_TIMES 200
    `endif

    `uvm_analysis_imp_decl(_instr)
    `uvm_analysis_imp_decl(_commit)
    `uvm_analysis_imp_decl(_dmem)

    `include "item/instr_item.svh"
    `include "item/dmem_item.svh"
    `include "item/probe_item.svh"
    `include "item/program_image.svh"

    `include "sequence/instr_sequence.svh"
    `include "sequence/dmem_sequence.svh"
    `include "sequence/program_sequence.svh"

    `include "agent/fetch_instr_agent/fetch_instr_sequencer.svh"
    `include "agent/fetch_instr_agent/fetch_instr_driver.svh"
    `include "agent/fetch_instr_agent/fetch_instr_monitor.svh"
    `include "agent/fetch_instr_agent/fetch_instr_agent.svh"
    `include "agent/program_agent/program_responder.svh"
    `include "agent/program_agent/program_agent.svh"

    `include "agent/dmem_agent/dmem_sequencer.svh"
    `include "agent/dmem_agent/dmem_driver.svh"
    `include "agent/dmem_agent/dmem_monitor.svh"
    `include "agent/dmem_agent/dmem_agent.svh"

    `include "agent/commit_agent/commit_monitor.svh"
    `include "agent/commit_agent/commit_agent.svh"

    `include "scoreboard/mycore_scoreboard.svh"
    `include "env/mycore_env.svh"
    `include "env/program_env.svh"

    `include "test/base_test/mycore_test.svh"
    `include "test/r_type_test/r_type_item.svh"
    `include "test/r_type_test/r_type_scoreboard.svh"
    `include "test/r_type_test/r_type_test.svh"
    `include "test/program_test/program_scoreboard.svh"
    `include "test/program_test/program_test.svh"

endpackage

`endif
