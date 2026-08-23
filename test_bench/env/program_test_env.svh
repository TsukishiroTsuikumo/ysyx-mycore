class program_test_env extends uvm_env;

    `uvm_component_utils(program_test_env)

    typedef axi_observer #(32, 32, 2, 1, 1) shared_axi_observer_t;

    retire_agent         rt_agent;
    cache_system_monitor cache_mon;
    dcache_agent         dc_agent;
    shared_axi_observer_t axi_observer;

    mycore_scoreboard scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        rt_agent   = retire_agent::type_id::create("rt_agent", this);
        cache_mon  = cache_system_monitor::type_id::create("cache_mon", this);
        dc_agent   = dcache_agent::type_id::create("dc_agent", this);
        uvm_config_db#(bit)::set(
            this, "axi_observer", "require_cache_line_traffic", 1'b1);
        // The frontend may have one legal speculative fetch outstanding when
        // a program test reaches its target retirement count.
        uvm_config_db#(bit)::set(
            this, "axi_observer", "require_quiescent_end", 1'b0);
        axi_observer = shared_axi_observer_t::type_id::create(
            "axi_observer", this);
        scoreboard = mycore_scoreboard::type_id::create("scoreboard", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        dc_agent.monitor.data_port.connect(scoreboard.dmem_ap);
        rt_agent.monitor.analysis_port.connect(scoreboard.retire_imp);
    endfunction

endclass
