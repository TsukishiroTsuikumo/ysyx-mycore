class commit_monitor extends uvm_monitor;
    `uvm_component_utils(commit_monitor)

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
            `uvm_fatal("COMMIT_MONITOR", "Failed to get probe interface")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        probe_item item;
        int unsigned retire_time = 0;
        test_done = uvm_event_pool::get_global("test_done");
        forever begin
            @(posedge probe.clk);
            uvm_wait_for_nba_region();
            if(probe.reset) begin
                retire_time = 0;
                continue;
            end
            if(probe.retire) begin
                item = probe_item::type_id::create("item");
                item.retire = probe.retire;
                item.commit = probe.commit;
                item.rd_addr = probe.rd_addr;
                item.rd_value = probe.rd_data;
                item.pc = probe.pc;
                item.instr = probe.instr;
                analysis_port.write(item);

                retire_time = retire_time + 1;
            end
            if(retire_time >= `TEST_TIMES) begin
                test_done.trigger();
                retire_time = 0;
            end
        end
    endtask

endclass
