class mycore_test extends uvm_test;
    `uvm_component_utils(mycore_test)

    virtual mycore_if vif;
    virtual state_probe_if probe_vif;
    mycore_agent_config agent_cfg;
    mycore_env env;
    mycore_sequence seq;
    int unsigned target_commits;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent_cfg = mycore_agent_config::type_id::create("agent_cfg");
        uvm_config_db#(mycore_agent_config)::set(this, "env.agent", "agent_cfg", agent_cfg);
        env = mycore_env::type_id::create("env", this);
        if (!uvm_config_db#(virtual state_probe_if)::get(this, "", "vif", probe_vif))
            `uvm_fatal("NOVIF", "test cannot get state_probe_if")
    endfunction

    virtual task run_phase(uvm_phase phase);
        int unsigned commit_count;

        phase.raise_objection(this);

        target_commits = `TEST_TIMES;
        void'($value$plusargs("TEST_TIMES=%d", target_commits));

        seq = mycore_sequence::type_id::create("seq");
        seq.num_items = target_commits;

        commit_count = 0;
        fork
            seq.start(env.agent.sequencer);
        join_none

        forever begin
            @(posedge probe_vif.clk);
            uvm_wait_for_nba_region();
            if (probe_vif.reset) begin
                commit_count = 0;
            end
            else if (probe_vif.wb_en) begin
                commit_count++;
                if (commit_count >= target_commits) begin
                    break;
                end
            end
        end
        disable fork;

        @(posedge env.agent.vif.clk);
        env.agent.vif.pm_rd <= 32'h00000013;
        repeat (2) @(posedge env.agent.vif.clk);

        phase.drop_objection(this);
    endtask

endclass
