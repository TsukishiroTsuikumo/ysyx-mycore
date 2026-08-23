`ifndef YSYX_CACHE_AGENT_SVH
`define YSYX_CACHE_AGENT_SVH

class cache_agent extends uvm_agent;
    `uvm_component_utils(cache_agent)
    cache_sequencer sequencer;
    cache_driver driver;
    cache_monitor monitor;
    uvm_analysis_port #(cache_transaction) analysis_port;

    function new(string name = "cache_agent", uvm_component parent = null);
        super.new(name, parent);
        analysis_port = new("analysis_port", this);
    endfunction
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = cache_sequencer::type_id::create("sequencer", this);
        driver = cache_driver::type_id::create("driver", this);
        monitor = cache_monitor::type_id::create("monitor", this);
    endfunction
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
        monitor.analysis_port.connect(analysis_port);
    endfunction
endclass

`endif
