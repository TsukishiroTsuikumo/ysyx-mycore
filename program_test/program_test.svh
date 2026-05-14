class program_test extends mycore_test;
    `uvm_component_utils(program_test)

    uvm_event#(uvm_object) done_ev;
    int unsigned timeout_cycles;
    
    function new(string name="program_test", uvm_component parent);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        uvm_test::build_phase(phase);

        mycore_monitor::type_id::set_type_override(program_monitor::get_type());
        mycore_scoreboard::type_id::set_type_override(program_scoreboard::get_type());

        agent_cfg = mycore_agent_config::type_id::create("agent_cfg");
        agent_cfg.agent_type = UVM_PASSIVE;
        uvm_config_db#(mycore_agent_config)::set(this, "env.agent", "agent_cfg", agent_cfg);
        env = mycore_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        bit done_seen;

        phase.raise_objection(this);

        timeout_cycles = 10000;
        done_seen = 1'b0;
        void'($value$plusargs("PROGRAM_TIMEOUT=%d", timeout_cycles));

        done_ev = uvm_event_pool::get_global("program_done");
        done_ev.reset();

        `uvm_info("PROGRAM_TEST",
                  $sformatf("passive program test started, timeout=%0d cycles", timeout_cycles),
                  UVM_LOW)

        fork
            begin
                done_ev.wait_ptrigger();
                done_seen = 1'b1;
            end
            begin
                repeat (timeout_cycles) @(posedge env.agent.vif.clk);
            end
        join_any
        disable fork;

        if (!done_seen) begin
            `uvm_error("PROGRAM_TIMEOUT",
                       $sformatf("program did not finish within %0d cycles", timeout_cycles))
        end

        repeat (5) @(posedge env.agent.vif.clk);

        phase.drop_objection(this);
    endtask

endclass
