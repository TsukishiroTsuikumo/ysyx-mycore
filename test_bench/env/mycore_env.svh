class mycore_env extends uvm_env;

    `uvm_component_utils(mycore_env)

    fetch_instr_agent if_agent;
    dmem_agent dm_agent;
    commit_agent cm_agent;

    mycore_scoreboard scoreboard;


    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if_agent = fetch_instr_agent::type_id::create("if_agent", this);
        dm_agent = dmem_agent::type_id::create("dm_agent", this);
        cm_agent = commit_agent::type_id::create("cm_agent", this);
        scoreboard = mycore_scoreboard::type_id::create("scoreboard", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if_agent.if_monitor.analysis_port.connect(scoreboard.instr_imp);
        dm_agent.monitor.analysis_port.connect(scoreboard.dmem_ap);
        cm_agent.cm_monitor.ap.connect(scoreboard.commit_imp);
    endfunction

endclass
