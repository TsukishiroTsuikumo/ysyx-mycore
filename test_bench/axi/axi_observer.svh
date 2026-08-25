`ifndef YSYX_AXI_OBSERVER_SVH
`define YSYX_AXI_OBSERVER_SVH

// Reusable passive AXI observer. It packages the transaction monitor and the
// explicit coverage/acceptance subscriber so existing environments only need
// to instantiate one component.
class axi_observer #(
    int unsigned ADDR_WIDTH  = 32,
    int unsigned DATA_WIDTH  = 32,
    int unsigned ID_WIDTH    = 2,
    int unsigned USER_WIDTH  = 1,
    int unsigned OWNER_WIDTH = 1
) extends uvm_env;

    typedef axi_observer #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) this_type;
    typedef axi_monitor #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) monitor_t;
    typedef axi_coverage #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) coverage_t;

    `uvm_component_param_utils(this_type)

    monitor_t  monitor;
    coverage_t coverage;

    bit require_cache_line_traffic;
    bit require_quiescent_end;

    function new(string name = "axi_observer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        void'(uvm_config_db#(bit)::get(
            this, "", "require_cache_line_traffic",
            require_cache_line_traffic));
        void'(uvm_config_db#(bit)::get(
            this, "", "require_quiescent_end", require_quiescent_end));

        uvm_config_db#(bit)::set(
            this, "coverage", "require_cache_line_traffic",
            require_cache_line_traffic);
        uvm_config_db#(bit)::set(
            this, "monitor", "require_quiescent_end",
            require_quiescent_end);

        monitor  = monitor_t::type_id::create("monitor", this);
        coverage = coverage_t::type_id::create("coverage", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        monitor.analysis_port.connect(coverage.analysis_export);
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("AXI_OBSERVER", $sformatf(
            "shared AXI observer active; require_cache_line_traffic=%0d require_quiescent_end=%0d",
            require_cache_line_traffic, require_quiescent_end), UVM_LOW)
    endfunction

endclass

`endif
