`ifndef YSYX_AXI_MASTER_TEST_SVH
`define YSYX_AXI_MASTER_TEST_SVH

class axi_master_test extends uvm_test;
    localparam int unsigned ADDR_WIDTH  = 32;
    localparam int unsigned DATA_WIDTH  = 32;
    localparam int unsigned ID_WIDTH    = 2;
    localparam int unsigned USER_WIDTH  = 1;
    localparam int unsigned OWNER_WIDTH = 1;

    typedef axi_agent #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) agent_t;
    typedef axi_coverage #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) coverage_t;
    typedef axi_master_sequence #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) sequence_t;
    typedef virtual axi_if #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) axi_vif_t;

    `uvm_component_utils(axi_master_test)

    agent_t agent;
    coverage_t coverage;
    axi_vif_t vif;
    sequence_t master_seq;

    function new(string name = "axi_master_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("AXI_MASTER_TEST", "Failed to get axi_if virtual interface")
        end

        uvm_config_db#(uvm_active_passive_enum)::set(
            this, "agent", "is_active", UVM_ACTIVE);
        uvm_config_db#(bit)::set(
            this, "agent.monitor", "require_quiescent_end", 1'b1);
        uvm_config_db#(bit)::set(
            this, "coverage", "require_backpressure_coverage", 1'b1);
        uvm_config_db#(bit)::set(
            this, "coverage", "require_owner_coverage", 1'b1);
        uvm_config_db#(bit)::set(
            this, "coverage", "require_cache_line_traffic", 1'b1);
        uvm_config_db#(bit)::set(
            this, "coverage", "require_error_response_coverage", 1'b1);
        uvm_config_db#(bit)::set(
            this, "coverage", "require_partial_strobe_coverage", 1'b1);

        agent = agent_t::type_id::create("agent", this);
        coverage = coverage_t::type_id::create("coverage", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.analysis_port.connect(coverage.analysis_export);
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        if (agent.is_active != UVM_ACTIVE || agent.sequencer == null ||
            agent.driver == null) begin
            `uvm_fatal("AXI_MASTER_TEST",
                "AXI agent was not elaborated in active mode")
        end
        master_seq = sequence_t::type_id::create("master_seq");
        master_seq.start(agent.sequencer);
        repeat (10) @(posedge vif.aclk);
        phase.drop_objection(this);
    endtask

    virtual function void report_phase(uvm_phase phase);
        uvm_report_server report_server;
        int unsigned error_total;
        int unsigned transaction_total;
        int unsigned sequence_errors;
        int unsigned check_total;
        int unsigned driver_reads;
        int unsigned driver_writes;

        super.report_phase(phase);
        report_server = uvm_report_server::get_server();
        error_total = report_server.get_severity_count(UVM_ERROR) +
                      report_server.get_severity_count(UVM_FATAL);
        transaction_total = 0;
        sequence_errors = 1;
        check_total = 0;
        if (master_seq != null) begin
            transaction_total = master_seq.completed_transactions;
            sequence_errors = master_seq.error_count;
            check_total = master_seq.check_count;
        end
        driver_reads = (agent == null || agent.driver == null) ? 0 :
                       agent.driver.completed_read_count;
        driver_writes = (agent == null || agent.driver == null) ? 0 :
                        agent.driver.completed_write_count;

        if (transaction_total != 19 || sequence_errors != 0 ||
            check_total != 58 || driver_reads != 13 || driver_writes != 6 ||
            error_total != 0) begin
            `uvm_error("AXI_ACTIVE_UVM_TEST", $sformatf(
                "FAIL transactions=%0d sequence_errors=%0d reads=%0d writes=%0d uvm_errors=%0d",
                transaction_total, sequence_errors, driver_reads,
                driver_writes, error_total))
        end
        else begin
            `uvm_info("AXI_ACTIVE_UVM_TEST", $sformatf(
                "PASS transactions=%0d checks=%0d reads=%0d writes=%0d",
                transaction_total, check_total, driver_reads, driver_writes),
                UVM_NONE)
        end
    endfunction

endclass

class axi_random_stress_test extends uvm_test;
    localparam int unsigned ADDR_WIDTH  = 32;
    localparam int unsigned DATA_WIDTH  = 32;
    localparam int unsigned ID_WIDTH    = 2;
    localparam int unsigned USER_WIDTH  = 1;
    localparam int unsigned OWNER_WIDTH = 1;

    typedef axi_agent #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) agent_t;
    typedef axi_coverage #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) coverage_t;
    typedef axi_random_stress_sequence #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) sequence_t;
    typedef virtual axi_if #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) axi_vif_t;

    `uvm_component_utils(axi_random_stress_test)

    agent_t agent;
    coverage_t coverage;
    axi_vif_t vif;
    sequence_t random_seq;

    function new(
        string name = "axi_random_stress_test",
        uvm_component parent = null
    );
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("AXI_RANDOM_TEST",
                "Failed to get axi_if virtual interface")
        end

        uvm_config_db#(uvm_active_passive_enum)::set(
            this, "agent", "is_active", UVM_ACTIVE);
        uvm_config_db#(bit)::set(
            this, "agent.monitor", "require_quiescent_end", 1'b1);
        uvm_config_db#(bit)::set(
            this, "coverage", "require_backpressure_coverage", 1'b1);
        uvm_config_db#(bit)::set(
            this, "coverage", "require_owner_coverage", 1'b1);
        uvm_config_db#(bit)::set(
            this, "coverage", "require_cache_line_traffic", 1'b1);
        uvm_config_db#(bit)::set(
            this, "coverage", "require_error_response_coverage", 1'b1);
        uvm_config_db#(bit)::set(
            this, "coverage", "require_partial_strobe_coverage", 1'b1);
        uvm_config_db#(bit)::set(
            this, "coverage", "require_random_stress_coverage", 1'b1);

        agent = agent_t::type_id::create("agent", this);
        coverage = coverage_t::type_id::create("coverage", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.analysis_port.connect(coverage.analysis_export);
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        if (agent.is_active != UVM_ACTIVE || agent.sequencer == null ||
            agent.driver == null) begin
            `uvm_fatal("AXI_RANDOM_TEST",
                "AXI agent was not elaborated in active mode")
        end
        random_seq = sequence_t::type_id::create("random_seq");
        random_seq.start(agent.sequencer);
        repeat (10) @(posedge vif.aclk);
        phase.drop_objection(this);
    endtask

    function bit queues_empty();
        if (agent == null || agent.monitor == null) return 1'b0;
        return (agent.monitor.aw_q.size() == 0) &&
               (agent.monitor.completed_w_q.size() == 0) &&
               (agent.monitor.current_w == null) &&
               (agent.monitor.write_response_q.size() == 0) &&
               (agent.monitor.read_q.size() == 0);
    endfunction

    function bit delay_bins_complete();
        if (random_seq == null) return 1'b0;
        for (int unsigned i = 0; i < 3; i++) begin
            if (random_seq.address_delay_bucket_hits[i] == 0 ||
                random_seq.beat_delay_bucket_hits[i] == 0 ||
                random_seq.response_delay_bucket_hits[i] == 0)
                return 1'b0;
        end
        return 1'b1;
    endfunction

    function bit all_random_gates_pass();
        if (random_seq == null || agent == null || agent.driver == null ||
            agent.monitor == null || coverage == null)
            return 1'b0;
        if (random_seq.completed_transactions != 64 ||
            random_seq.completed_reads != 32 ||
            random_seq.completed_writes != 32 ||
            random_seq.successful_write_count != 30 ||
            random_seq.used_okay_addr_q.size() != 30 ||
            random_seq.paired_readbacks != 30 ||
            random_seq.error_write_unchanged != 2 ||
            random_seq.pending_addr_q.size() != 0 ||
            random_seq.pending_resp_q.size() != 0 ||
            random_seq.pending_pair_index_q.size() != 0 ||
            random_seq.pending_error_contract_q.size() != 0 ||
            random_seq.error_count != 0 || !delay_bins_complete())
            return 1'b0;
        if (agent.driver.completed_read_count != 32 ||
            agent.driver.completed_write_count != 32 ||
            agent.monitor.aw_count != 32 ||
            agent.monitor.w_burst_count != 32 ||
            agent.monitor.b_count != 32 ||
            agent.monitor.ar_count != 32 ||
            agent.monitor.r_burst_count != 32 || !queues_empty())
            return 1'b0;
        if (coverage.total_read != 32 || coverage.total_write != 32 ||
            !coverage.read_owner_hits.exists(0) ||
            coverage.read_owner_hits[0] < 8 ||
            !coverage.read_owner_hits.exists(1) ||
            coverage.read_owner_hits[1] < 8 ||
            coverage.full_strobe_write_ok == 0 ||
            coverage.single_byte_strobe_write_ok == 0 ||
            coverage.multi_byte_strobe_write_ok == 0 ||
            coverage.zero_strobe_write_ok == 0 ||
            coverage.read_response_txn_hits[AXI_RESP_OKAY] == 0 ||
            coverage.write_response_txn_hits[AXI_RESP_OKAY] == 0 ||
            coverage.expected_read_slverr_ok != 1 ||
            coverage.expected_read_decerr_ok != 1 ||
            coverage.expected_write_slverr_ok != 1 ||
            coverage.expected_write_decerr_ok != 1 ||
            coverage.protocol_error_count() != 0 ||
            coverage.acceptance_errors != 0)
            return 1'b0;
        for (int unsigned i = 0; i < 5; i++) begin
            if (coverage.channel_backpressure_hits[i] < 4 ||
                coverage.channel_stall_cycles[i] < 8)
                return 1'b0;
        end
        return 1'b1;
    endfunction

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (!all_random_gates_pass()) begin
            if (coverage != null) coverage.acceptance_errors++;
            `uvm_error("AXI_RANDOM_TEST",
                "one or more random stress acceptance gates failed")
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        uvm_report_server report_server;
        int unsigned error_total;
        bit pass;

        super.report_phase(phase);
        report_server = uvm_report_server::get_server();
        error_total = report_server.get_severity_count(UVM_ERROR) +
                      report_server.get_severity_count(UVM_FATAL);
        pass = all_random_gates_pass() && (error_total == 0);

        if (random_seq != null && coverage != null) begin
            $display("AXI_RANDOM_COVERAGE status=%s seed=0x%08x txns=%0d reads=%0d writes=%0d unique_okay_writes=%0d paired_readbacks=%0d error_write_unchanged=%0d i_reads=%0d d_reads=%0d addr_delay_0=%0d addr_delay_1_3=%0d addr_delay_4_7=%0d beat_delay_0=%0d beat_delay_1_3=%0d beat_delay_4_7=%0d resp_delay_0=%0d resp_delay_1_3=%0d resp_delay_4_7=%0d aw_bp_txns=%0d aw_stall_cycles=%0d w_bp_txns=%0d w_stall_cycles=%0d b_bp_txns=%0d b_stall_cycles=%0d ar_bp_txns=%0d ar_stall_cycles=%0d r_bp_txns=%0d r_stall_cycles=%0d wstrb_full=%0d wstrb_single=%0d wstrb_multi=%0d wstrb_zero=%0d read_okay=%0d write_okay=%0d owner_id_errors=%0d shape_errors=%0d protocol_errors=%0d queues_empty=%0d",
                pass ? "PASS" : "FAIL", random_seq.random_seed,
                random_seq.completed_transactions,
                random_seq.completed_reads, random_seq.completed_writes,
                random_seq.used_okay_addr_q.size(),
                random_seq.paired_readbacks,
                random_seq.error_write_unchanged,
                coverage.read_owner_hits.exists(0) ?
                    coverage.read_owner_hits[0] : 0,
                coverage.read_owner_hits.exists(1) ?
                    coverage.read_owner_hits[1] : 0,
                random_seq.address_delay_bucket_hits[0],
                random_seq.address_delay_bucket_hits[1],
                random_seq.address_delay_bucket_hits[2],
                random_seq.beat_delay_bucket_hits[0],
                random_seq.beat_delay_bucket_hits[1],
                random_seq.beat_delay_bucket_hits[2],
                random_seq.response_delay_bucket_hits[0],
                random_seq.response_delay_bucket_hits[1],
                random_seq.response_delay_bucket_hits[2],
                coverage.channel_backpressure_hits[0],
                coverage.channel_stall_cycles[0],
                coverage.channel_backpressure_hits[1],
                coverage.channel_stall_cycles[1],
                coverage.channel_backpressure_hits[2],
                coverage.channel_stall_cycles[2],
                coverage.channel_backpressure_hits[3],
                coverage.channel_stall_cycles[3],
                coverage.channel_backpressure_hits[4],
                coverage.channel_stall_cycles[4],
                coverage.full_strobe_write_ok,
                coverage.single_byte_strobe_write_ok,
                coverage.multi_byte_strobe_write_ok,
                coverage.zero_strobe_write_ok,
                coverage.read_response_txn_hits[AXI_RESP_OKAY],
                coverage.write_response_txn_hits[AXI_RESP_OKAY],
                coverage.owner_id_errors,
                coverage.cache_line_shape_errors,
                coverage.protocol_error_count(), queues_empty());
            $display("AXI_ERROR_RESPONSE_COVERAGE status=%s read_slverr=%0d read_decerr=%0d write_slverr=%0d write_decerr=%0d protocol_errors=%0d",
                pass ? "PASS" : "FAIL",
                coverage.expected_read_slverr_ok,
                coverage.expected_read_decerr_ok,
                coverage.expected_write_slverr_ok,
                coverage.expected_write_decerr_ok,
                coverage.protocol_error_count());
        end
        if (pass)
            `uvm_info("AXI_RANDOM_UVM_TEST", "PASS", UVM_NONE)
        else
            `uvm_error("AXI_RANDOM_UVM_TEST", $sformatf(
                "FAIL uvm_errors=%0d", error_total))
    endfunction

endclass

`endif
