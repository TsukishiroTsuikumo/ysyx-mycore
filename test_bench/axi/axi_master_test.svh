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

`endif
