class mycore_test extends uvm_test;
    `uvm_component_utils(mycore_test)

    mycore_env env;
    instr_sequence seq;

    virtual icache_if ic_vif;
    virtual probe_if  probe_vif;

    int unsigned target_commits;
    int unsigned timeout_cycles;

    function new(string name = "mycore_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = mycore_env::type_id::create("env", this);
        if(!uvm_config_db#(virtual icache_if)::get(this, "", "vif", ic_vif)) begin
            `uvm_fatal("MYCORE_TEST", "Failed to get icache interface")
        end
        if(!uvm_config_db#(virtual probe_if)::get(this, "", "probe", probe_vif)) begin
            `uvm_fatal("MYCORE_TEST", "Failed to get probe interface")
        end
    endfunction

    virtual task reset_and_init();
        ic_vif.rst <= 1'b1;
        probe_vif.reset <= 1'b1;
        repeat (5) @(posedge ic_vif.clk);
        @(negedge ic_vif.clk);
        probe_vif.request_reg_init();
        ic_vif.rst <= 1'b0;
        probe_vif.reset <= 1'b0;
        repeat (2) @(posedge ic_vif.clk);
    endtask

    virtual task run_phase(uvm_phase phase);
        int unsigned commit_count;
        bit reached_target;
        bit timeout_hit;

        phase.raise_objection(this);

        reset_and_init();

        target_commits = `TEST_TIMES;
        void'($value$plusargs("TARGET_COMMITS=%d", target_commits));
        timeout_cycles = target_commits * 200 + 2000;
        void'($value$plusargs("TIMEOUT_CYCLES=%d", timeout_cycles));

        seq = instr_sequence::type_id::create("seq");
        fork
            seq.start(env.if_agent.if_sequencer);
        join_none

        commit_count = 0;
        reached_target = 1'b0;
        timeout_hit = 1'b0;

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
                timeout_cycles, commit_count, target_commits))
        end

        uvm_event_pool::get_global("test_done").trigger();
        repeat (10) @(posedge probe_vif.clk);

        phase.drop_objection(this);
    endtask

endclass
