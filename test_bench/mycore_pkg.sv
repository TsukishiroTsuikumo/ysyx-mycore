`ifndef NEW_MYCORE_PKG_SV
`define NEW_MYCORE_PKG_SV
`timescale 1ns/1ps

package mycore_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `ifndef TEST_TIMES
        `define TEST_TIMES 5000
    `endif

    `uvm_analysis_imp_decl(_instr)
    `uvm_analysis_imp_decl(_commit)
    `uvm_analysis_imp_decl(_dmem)

    `include "cmodel_dpi.svh"

    `include "item/instr_item.svh"
    `include "item/fetch_data_item.svh"
    `include "item/dcache_item.svh"
    `include "item/probe_item.svh"
    `include "item/icache_item.svh"
    `include "item/program_image.svh"

    `include "sequence/instr_sequence.svh"
    `include "sequence/fetch_data_sequence.svh"
    `include "sequence/icache_sequence.svh"
    `include "sequence/program_sequence.svh"

    `include "agent/fetch_instr_agent/fetch_instr_sequencer.svh"
    `include "agent/fetch_instr_agent/fetch_instr_driver.svh"
    `include "agent/fetch_instr_agent/fetch_instr_monitor.svh"
    `include "agent/fetch_instr_agent/fetch_instr_agent.svh"
    `include "agent/icache_agent/icache_sequencer.svh"
    `include "agent/icache_agent/icache_driver.svh"
    `include "agent/icache_agent/icache_monitor.svh"
    `include "agent/icache_agent/icache_agent.svh"

    `include "agent/fetch_data_agent/fetch_data_sequencer.svh"
    `include "agent/fetch_data_agent/fetch_data_driver.svh"
    `include "agent/fetch_data_agent/fetch_data_monitor.svh"
    `include "agent/fetch_data_agent/fetch_data_agent.svh"
    `include "agent/dcache_agent/dcache_sequencer.svh"
    `include "agent/dcache_agent/dcache_driver.svh"
    `include "agent/dcache_agent/dcache_monitor.svh"
    `include "agent/dcache_agent/dcache_agent.svh"

    `include "agent/commit_agent/commit_monitor.svh"
    `include "agent/commit_agent/commit_agent.svh"
    `include "agent/cache_system_agent/cache_system_monitor.svh"

    `include "scoreboard/mycore_scoreboard.svh"
    `include "env/instr_test_env.svh"
    `include "env/program_test_env.svh"
    `include "env/cache_test_env.svh"

    `include "test/base_test/instr_base_test.svh"
    `include "test/base_test/program_base_test.svh"
    `include "test/base_test/cache_base_test.svh"
    `include "test/core_only_test/calc_test/calc_item.svh"
    `include "test/core_only_test/calc_test/calc_scoreboard.svh"
    `include "test/core_only_test/calc_test/calc_test.svh"
    `include "test/core_only_test/ld_test/ld_item.svh"
    `include "test/core_only_test/st_test/st_item.svh"
    `include "test/core_only_test/jp_link_test/jp_link_item.svh"
    `include "test/core_only_test/ld_test/ld_scoreboard.svh"
    `include "test/core_only_test/st_test/st_scoreboard.svh"
    `include "test/core_only_test/jp_link_test/jp_link_scoreboard.svh"
    `include "test/program_test/program_scoreboard.svh"
    `include "test/core_only_test/ld_test/ld_test.svh"
    `include "test/core_only_test/st_test/st_test.svh"
    `include "test/core_only_test/jp_link_test/jp_link_test.svh"
    `include "test/program_test/program_test.svh"
    `include "test/program_test/mem_image_test.svh"
    `include "test/cache_test/icache_test.svh"
    `include "test/cache_test/dcache_test.svh"

endpackage

`endif
