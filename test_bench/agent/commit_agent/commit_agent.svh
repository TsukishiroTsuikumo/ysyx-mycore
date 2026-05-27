class commit_agent extends uvm_agent;
    `uvm_component_utils(commit_agent)

    commit_monitor cm_monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cm_monitor = commit_monitor::type_id::create("cm_monitor", this);
    endfunction

endclass
