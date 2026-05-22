class mycore_test extends uvm_test;
    `uvm_component_utils(mycore_test)

    virtual mycore_if vif;
    virtual state_probe_if probe_vif;
    mycore_agent_config agent_cfg;
    mycore_env env;
    mycore_sequence seq;
    int unsigned target_commits;
    int unsigned timeout_cycles;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent_cfg = mycore_agent_config::type_id::create("agent_cfg");
        uvm_config_db#(mycore_agent_config)::set(this, "env.agent", "agent_cfg", agent_cfg);
        env = mycore_env::type_id::create("env", this);
        if (!uvm_config_db#(virtual mycore_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "test cannot get mycore_if")
        if (!uvm_config_db#(virtual state_probe_if)::get(this, "", "vif", probe_vif))
            `uvm_fatal("NOVIF", "test cannot get state_probe_if")
    endfunction

    virtual task reset_and_init();
        vif.reset <= 1'b1;
        repeat (4) @(posedge vif.clk);
        @(negedge vif.clk);
        probe_vif.request_reg_init();
        vif.reset <= 1'b0;
        @(posedge vif.clk);
    endtask

    virtual task run_phase(uvm_phase phase);
        int unsigned commit_count;
        bit reached_target;
        bit timeout_hit;

        phase.raise_objection(this);

        reset_and_init();

        target_commits = `TEST_TIMES;
        void'($value$plusargs("TEST_TIMES=%d", target_commits));
        timeout_cycles = target_commits * 100 + 1000;
        void'($value$plusargs("UVM_TIMEOUT=%d", timeout_cycles));

        seq = mycore_sequence::type_id::create("seq");
        seq.num_items = target_commits;

        commit_count = 0;
        reached_target = 1'b0;
        timeout_hit = 1'b0;
        fork
            seq.start(env.agent.sequencer);
        join_none

        fork
            begin
                forever begin
                    @(posedge probe_vif.clk);
                    uvm_wait_for_nba_region();
                    if (probe_vif.reset) begin
                        commit_count = 0;
                    end
                    else if (probe_vif.commit) begin
                        commit_count++;
                        if (commit_count >= target_commits) begin
                            reached_target = 1'b1;
                            break;
                        end
                    end
                end
            end
            begin
                repeat (timeout_cycles) @(posedge probe_vif.clk);
                timeout_hit = 1'b1;
            end
        join_any
        disable fork;

        if (timeout_hit && !reached_target) begin
            `uvm_error("TEST_TIMEOUT", $sformatf(
                "timeout after %0d cycles: commits=%0d target=%0d",
                timeout_cycles, commit_count, target_commits
            ))
        end

        @(posedge env.agent.vif.clk);
        env.agent.vif.pm_resp_data <= 32'h00000013;
        repeat (2) @(posedge env.agent.vif.clk);

        phase.drop_objection(this);
    endtask

endclass
