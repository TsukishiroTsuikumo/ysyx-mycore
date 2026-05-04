class r_type_env extends mycore_env;
    `uvm_component_utils(r_type_env)

    r_type_scoreboard scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        scoreboard = r_type_scoreboard::type_id::create("scoreboard", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.act_port.connect(scoreboard.instr_imp);
    endfunction
endclass
