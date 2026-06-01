class st_test extends instr_base_test;
    `uvm_component_utils(st_test)

    virtual dcache_if dc_vif;

    function new(string name = "st_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        instr_item::type_id::set_type_override(st_item::get_type());
        mycore_scoreboard::type_id::set_type_override(st_scoreboard::get_type());
        super.build_phase(phase);
        if (!uvm_config_db#(virtual dcache_if)::get(this, "", "vif", dc_vif)) begin
            `uvm_fatal("ST_TEST", "Failed to get dcache interface")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        int unsigned write_count;
        bit reached_target;
        bit timeout_hit;

        phase.raise_objection(this);

        pre_reset_setup();
        reset_and_init();

        target_commits = `TEST_TIMES;
        void'($value$plusargs("TARGET_COMMITS=%d", target_commits));
        timeout_cycles = target_commits * 200 + 2000;
        void'($value$plusargs("TIMEOUT_CYCLES=%d", timeout_cycles));

        start_main_sequence();

        write_count = 0;
        reached_target = 1'b0;
        timeout_hit = 1'b0;

        fork
            begin
                forever begin
                    @(posedge dc_vif.clk);
                    if (!dc_vif.rst && dc_vif.req_wvalid && dc_vif.req_wready) begin
                        write_count++;
                        if (write_count >= target_commits) begin
                            reached_target = 1'b1;
                            break;
                        end
                    end
                end
            end
            begin
                repeat (timeout_cycles) @(posedge dc_vif.clk);
                timeout_hit = 1'b1;
            end
        join_any
        disable fork;

        if (timeout_hit && !reached_target) begin
            `uvm_error("TEST_TIMEOUT", $sformatf(
                "timeout after %0d cycles: stores=%0d target=%0d",
                timeout_cycles, write_count, target_commits))
        end

        uvm_event_pool::get_global("test_done").trigger();
        repeat (10) @(posedge dc_vif.clk);

        phase.drop_objection(this);
    endtask

endclass
