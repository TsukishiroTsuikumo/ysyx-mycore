class program_test_env extends uvm_env;

    `uvm_component_utils(program_test_env)

    commit_agent         cm_agent;
    cache_system_monitor cache_mon;
    dcache_agent         dc_agent;

    mycore_scoreboard scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cm_agent   = commit_agent::type_id::create("cm_agent", this);
        cache_mon  = cache_system_monitor::type_id::create("cache_mon", this);
        dc_agent   = dcache_agent::type_id::create("dc_agent", this);
        scoreboard = mycore_scoreboard::type_id::create("scoreboard", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        cache_mon.instr_port.connect(scoreboard.instr_imp);
        dc_agent.monitor.data_port.connect(scoreboard.dmem_ap);
        cm_agent.monitor.analysis_port.connect(scoreboard.commit_imp);
    endfunction

endclass
