class instr_test_env extends uvm_env;

    `uvm_component_utils(instr_test_env)

    fetch_instr_agent if_agent;
    fetch_data_agent  data_agent;
    commit_agent      cm_agent;

    mycore_scoreboard scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if_agent   = fetch_instr_agent::type_id::create("if_agent", this);
        data_agent = fetch_data_agent::type_id::create("data_agent", this);
        cm_agent   = commit_agent::type_id::create("cm_agent", this);
        scoreboard = mycore_scoreboard::type_id::create("scoreboard", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if_agent.monitor.analysis_port.connect(scoreboard.instr_imp);
        data_agent.monitor.analysis_port.connect(scoreboard.dmem_ap);
        cm_agent.monitor.analysis_port.connect(scoreboard.commit_imp);
    endfunction

endclass
