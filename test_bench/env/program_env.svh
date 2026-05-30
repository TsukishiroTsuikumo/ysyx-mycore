class program_env extends uvm_env;
    `uvm_component_utils(program_env)

    program_agent pg_agent;
    dmem_agent    dm_agent;
    commit_agent  cm_agent;
    mycore_scoreboard scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        pg_agent = program_agent::type_id::create("pg_agent", this);
        dm_agent = dmem_agent::type_id::create("dm_agent", this);
        cm_agent = commit_agent::type_id::create("cm_agent", this);
        scoreboard = mycore_scoreboard::type_id::create("scoreboard", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        pg_agent.responder.analysis_port.connect(scoreboard.instr_imp);
        dm_agent.monitor.analysis_port.connect(scoreboard.dmem_ap);
        cm_agent.monitor.analysis_port.connect(scoreboard.commit_imp);
    endfunction

endclass
