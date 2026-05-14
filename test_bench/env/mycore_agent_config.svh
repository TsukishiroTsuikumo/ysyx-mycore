class mycore_agent_config extends uvm_object;

    `uvm_object_utils(mycore_agent_config)

    uvm_active_passive_enum agent_type = UVM_ACTIVE;

    function new(string name = "mycore_agent_config");
        super.new(name);
    endfunction

endclass
