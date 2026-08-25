class retire_monitor extends uvm_monitor;
    `uvm_component_utils(retire_monitor)

    virtual probe_if probe;
    uvm_analysis_port#(probe_item) analysis_port;
    uvm_event#(uvm_object) test_done;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        analysis_port = new("analysis_port", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual probe_if)::get(this, "", "probe", probe)) begin
            `uvm_fatal("RETIRE_MONITOR", "Failed to get probe interface")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        probe_item item;
        int unsigned retire_time = 0;
        int unsigned lane;
        test_done = uvm_event_pool::get_global("test_done");
        forever begin
            @(posedge probe.clk);
            uvm_wait_for_nba_region();
            if(probe.reset) begin
                retire_time = 0;
                continue;
            end
            for (lane = 0; lane < 2; lane++) begin
                if (probe.retire_valid[lane]) begin
                    item = probe_item::type_id::create(
                        $sformatf("item_lane%0d", lane));
                    item.retire = 1'b1;
                    item.commit = probe.retire_rd_write[lane];
                    item.rd_addr = probe.retire_rd_addr[lane*5 +: 5];
                    item.rd_value = probe.retire_rd_data[lane*32 +: 32];
                    item.pc = probe.retire_pc[lane*32 +: 32];
                    item.instr = probe.retire_instr[lane*32 +: 32];
                    analysis_port.write(item);

                    retire_time = retire_time + 1;
                end
            end
            if(retire_time >= `TEST_TIMES) begin
                test_done.trigger();
                retire_time = 0;
            end
        end
    endtask

endclass
