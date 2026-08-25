`ifndef YSYX_AXI_AGENT_SVH
`define YSYX_AXI_AGENT_SVH

class axi_agent #(
    int unsigned ADDR_WIDTH  = 32,
    int unsigned DATA_WIDTH  = 32,
    int unsigned ID_WIDTH    = 2,
    int unsigned USER_WIDTH  = 1,
    int unsigned OWNER_WIDTH = 1
) extends uvm_agent;

    typedef axi_agent #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) this_type;
    typedef axi_transaction #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) txn_t;
    typedef axi_sequencer #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) sequencer_t;
    typedef axi_driver #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) driver_t;
    typedef axi_monitor #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) monitor_t;

    `uvm_component_param_utils(this_type)

    uvm_active_passive_enum is_active;
    sequencer_t sequencer;
    driver_t    driver;
    monitor_t   monitor;
    uvm_analysis_port #(txn_t) analysis_port;

    function new(string name = "axi_agent", uvm_component parent = null);
        super.new(name, parent);
        analysis_port = new("analysis_port", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(uvm_active_passive_enum)::get(
            this, "", "is_active", is_active)) begin
            is_active = UVM_PASSIVE;
        end

        monitor = monitor_t::type_id::create("monitor", this);
        if (is_active == UVM_ACTIVE) begin
            sequencer = sequencer_t::type_id::create("sequencer", this);
            driver    = driver_t::type_id::create("driver", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        monitor.analysis_port.connect(analysis_port);
        if (is_active == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("AXI_AGENT", $sformatf(
            "mode=%s", (is_active == UVM_ACTIVE) ? "ACTIVE" : "PASSIVE"),
            UVM_LOW)
    endfunction

endclass

`endif
