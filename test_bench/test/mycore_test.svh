class mycore_test extends uvm_test;
    `uvm_component_utils(mycore_test)

    virtual mycore_if vif;
    mycore_env env;
    mycore_sequence seq;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = mycore_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        seq = mycore_sequence::type_id::create("seq");
        seq.start(env.agent.sequencer);

        @(posedge env.agent.vif.clk);
        env.agent.vif.pm_rd_in <= 32'b0;
        repeat (5) @(posedge env.agent.vif.clk);

        phase.drop_objection(this);
    endtask

endclass
