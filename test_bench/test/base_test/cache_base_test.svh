class cache_base_test extends uvm_test;
    `uvm_component_utils(cache_base_test)

    cache_test_env env;

    virtual icache_if ic_vif;
    virtual dcache_if dc_vif;
    virtual probe_if  probe_vif;

    int unsigned timeout_cycles;

    function new(string name = "cache_base_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = cache_test_env::type_id::create("env", this);
        if (!uvm_config_db#(virtual icache_if)::get(this, "", "vif", ic_vif)) begin
            `uvm_fatal("CACHE_BASE_TEST", "Failed to get icache interface")
        end
        if (!uvm_config_db#(virtual dcache_if)::get(this, "", "vif", dc_vif)) begin
            `uvm_fatal("CACHE_BASE_TEST", "Failed to get dcache interface")
        end
        if (!uvm_config_db#(virtual probe_if)::get(this, "", "probe", probe_vif)) begin
            `uvm_fatal("CACHE_BASE_TEST", "Failed to get probe interface")
        end
    endfunction

    virtual task reset_and_init();
        ic_vif.rst <= 1'b1;
        dc_vif.rst <= 1'b1;
        probe_vif.reset <= 1'b1;
        repeat (5) @(posedge ic_vif.clk);
        @(negedge ic_vif.clk);
        ic_vif.rst <= 1'b0;
        dc_vif.rst <= 1'b0;
        probe_vif.reset <= 1'b0;
        repeat (2) @(posedge ic_vif.clk);
    endtask

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        timeout_cycles = 2000;
        void'($value$plusargs("TIMEOUT_CYCLES=%d", timeout_cycles));

        reset_and_init();
        repeat (timeout_cycles) @(posedge ic_vif.clk);

        uvm_event_pool::get_global("test_done").trigger();
        phase.drop_objection(this);
    endtask

endclass
