class cache_test_env extends uvm_env;

    `uvm_component_utils(cache_test_env)

    icache_agent      ic_agent;
    dcache_agent      dc_agent;
    mycore_scoreboard scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ic_agent   = icache_agent::type_id::create("ic_agent", this);
        dc_agent   = dcache_agent::type_id::create("dc_agent", this);
        scoreboard = mycore_scoreboard::type_id::create("scoreboard", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        dc_agent.monitor.data_port.connect(scoreboard.dmem_ap);
    endfunction

endclass
