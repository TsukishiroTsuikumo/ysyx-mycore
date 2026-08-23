`ifndef YSYX_CACHE_TEST_SVH
`define YSYX_CACHE_TEST_SVH

class cache_uvm_test extends uvm_test;
    `uvm_component_utils(cache_uvm_test)

    cache_agent agent;
    cache_memory_model memory_model;
    cache_scoreboard scoreboard;
    cache_sequence test_seq;
    virtual cache_uvm_if vif;
    bit [28:0] semantic_bins;

    function new(string name = "cache_uvm_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual cache_uvm_if)::get(this, "", "vif", vif))
            `uvm_fatal("CACHE_TEST", "cache_uvm_if was not configured")
        agent = cache_agent::type_id::create("agent", this);
        memory_model = cache_memory_model::type_id::create("memory_model", this);
        scoreboard = cache_scoreboard::type_id::create("scoreboard", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.analysis_port.connect(scoreboard.analysis_export);
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        test_seq = cache_sequence::type_id::create("test_seq");
        test_seq.start(agent.sequencer);
        repeat (12) @(posedge vif.clk);
        phase.drop_objection(this);
    endtask

    function void calculate_bins();
        semantic_bins = '0;
        semantic_bins[0]  = scoreboard.ic_misses != 0;
        semantic_bins[1]  = scoreboard.ic_hits != 0;
        semantic_bins[2]  = scoreboard.ic_consecutive_misses != 0;
        semantic_bins[3]  = scoreboard.ic_same_set_misses >= 5;
        semantic_bins[4]  = scoreboard.ic_flush_invalidations != 0;
        semantic_bins[5]  = scoreboard.ic_reset_invalidations != 0;
        semantic_bins[6]  = scoreboard.ic_slverr >= 2;
        semantic_bins[7]  = scoreboard.ic_decerr >= 2;
        semantic_bins[8]  = scoreboard.dc_read_misses != 0;
        semantic_bins[9]  = scoreboard.dc_read_hits != 0;
        semantic_bins[10] = scoreboard.dc_write_misses != 0;
        semantic_bins[11] = scoreboard.dc_write_hits != 0;
        semantic_bins[12] = scoreboard.dc_dirty_writebacks != 0;
        semantic_bins[13] = scoreboard.dc_writeback_refetches != 0;
        semantic_bins[14] = scoreboard.dc_writeback_errors != 0;
        semantic_bins[15] = scoreboard.dc_dirty_retained != 0;
        semantic_bins[16] = scoreboard.dc_refill_errors >= 2;
        semantic_bins[17] = scoreboard.dc_raw_checks >= 8;
        semantic_bins[18] = &scoreboard.wstrb_bins[3:0];
        semantic_bins[19] = &scoreboard.wstrb_bins[5:4];
        semantic_bins[20] = scoreboard.wstrb_bins[6];
        semantic_bins[21] = scoreboard.wstrb_bins[7];
        semantic_bins[22] = scoreboard.dc_crossline_reads != 0;
        semantic_bins[23] = memory_model.response_delay_hits[0] != 0;
        semantic_bins[24] = memory_model.response_delay_hits[1] != 0;
        semantic_bins[25] = memory_model.response_delay_hits[2] != 0;
        semantic_bins[26] = memory_model.ready_backpressure_cycles != 0;
        semantic_bins[27] = memory_model.concurrent_pending_cycles != 0;
        // This bin is intentionally conjunctive: the passive monitor must see
        // a flush cancel an already accepted miss, and the active driver must
        // prove drain ordering, stale-fault suppression, and a correct fresh
        // refill before recording its pass.
        semantic_bins[28] = (scoreboard.ic_inflight_flushes == 1) &&
                            (agent.driver.ic_inflight_flush_drains == 1);
    endfunction

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        calculate_bins();
        if (semantic_bins !== {29{1'b1}})
            `uvm_error("CACHE_UVM_GATE", $sformatf(
                "missing semantic bins bitmap=0x%08x", ~semantic_bins))
        if (scoreboard.data_errors != 0 || scoreboard.order_errors != 0 ||
            !scoreboard.queues_empty())
            `uvm_error("CACHE_UVM_GATE", "scoreboard integrity/order gate failed")
        if (test_seq == null || test_seq.completed_operations != 52 ||
            agent.driver.completed_transactions != 52 ||
            agent.driver.ic_inflight_flush_drains != 1 ||
            scoreboard.completed_transactions != 54 ||
            scoreboard.read_checks != 32 || scoreboard.writes != 19 ||
            scoreboard.controls != 3 || scoreboard.ic_inflight_flushes != 1)
            `uvm_error("CACHE_UVM_GATE", "transaction accounting gate failed")
    endfunction

    virtual function void report_phase(uvm_phase phase);
        uvm_report_server server;
        int unsigned errors;
        int unsigned hits;
        bit pass;
        super.report_phase(phase);
        calculate_bins();
        hits = $countones(semantic_bins);
        server = uvm_report_server::get_server();
        errors = server.get_severity_count(UVM_ERROR) +
                 server.get_severity_count(UVM_FATAL);
        pass = (hits == 29) && scoreboard.queues_empty() &&
               scoreboard.data_errors == 0 && scoreboard.order_errors == 0 &&
               agent.driver.ic_inflight_flush_drains == 1 &&
               scoreboard.ic_inflight_flushes == 1 &&
               scoreboard.completed_transactions == 54 &&
               scoreboard.read_checks == 32 && scoreboard.writes == 19 &&
               scoreboard.controls == 3 && errors == 0;

        $display("CACHE_UVM_COVERAGE status=%s required=29 hit=%0d missing=%0d ic_hit=%0d ic_miss=%0d ic_consecutive_miss=%0d ic_clean_replace=%0d ic_flush=%0d ic_inflight_flush=%0d ic_reset=%0d ic_slverr=%0d ic_decerr=%0d dc_read_hit=%0d dc_read_miss=%0d dc_write_hit=%0d dc_write_miss=%0d dirty_writeback=%0d writeback_error=%0d dirty_retain=%0d refill_error=%0d raw=%0d wstrb=0x%02x crossline=%0d delay_bins=%0d/%0d/%0d backpressure_cycles=%0d concurrent_cycles=%0d",
                 pass ? "PASS" : "FAIL", hits, 29-hits,
                 scoreboard.ic_hits, scoreboard.ic_misses,
                 scoreboard.ic_consecutive_misses,
                 scoreboard.ic_same_set_misses >= 5,
                 scoreboard.ic_flush_invalidations,
                 agent.driver.ic_inflight_flush_drains,
                 scoreboard.ic_reset_invalidations,
                 scoreboard.ic_slverr, scoreboard.ic_decerr,
                 scoreboard.dc_read_hits, scoreboard.dc_read_misses,
                 scoreboard.dc_write_hits, scoreboard.dc_write_misses,
                 scoreboard.dc_dirty_writebacks,
                 scoreboard.dc_writeback_errors,
                 scoreboard.dc_dirty_retained,
                 scoreboard.dc_refill_errors, scoreboard.dc_raw_checks,
                 scoreboard.wstrb_bins, scoreboard.dc_crossline_reads,
                 memory_model.response_delay_hits[0],
                 memory_model.response_delay_hits[1],
                 memory_model.response_delay_hits[2],
                 memory_model.ready_backpressure_cycles,
                 memory_model.concurrent_pending_cycles);
        $display("CACHE_UVM_ORDER status=%s remaining_ic=%0d remaining_dc=%0d remaining_control=%0d order_errors=%0d data_errors=%0d",
                 pass ? "PASS" : "FAIL", scoreboard.expected_ic_q.size(),
                 scoreboard.expected_dc_addr_q.size(),
                 scoreboard.expected_control_q.size(),
                 scoreboard.order_errors, scoreboard.data_errors);
        $display("CACHE_UVM_TEST status=%s transactions=%0d checks=%0d reads=%0d writes=%0d controls=%0d uvm_errors=%0d",
                 pass ? "PASS" : "FAIL", scoreboard.completed_transactions,
                 scoreboard.read_checks, scoreboard.read_checks,
                 scoreboard.writes, scoreboard.controls, errors);
    endfunction
endclass

`endif
