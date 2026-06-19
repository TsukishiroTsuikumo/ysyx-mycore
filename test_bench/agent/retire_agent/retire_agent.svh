class retire_agent extends uvm_agent;
    `uvm_component_utils(retire_agent)

    retire_monitor monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        monitor = retire_monitor::type_id::create("monitor", this);
    endfunction

endclass
