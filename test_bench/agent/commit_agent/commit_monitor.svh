class commit_monitor extends uvm_monitor;
    `uvm_component_utils(commit_monitor)

    virtual probe_if probe;
    uvm_analysis_port#(probe_item) ap;
    uvm_event #(uvm_object) test_done;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual probe_if)::get(this, "", "probe", probe)) begin
            `uvm_fatal("COMMIT_MONITOR", "Failed to get probe interface")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        probe_item item;
        int unsigned commit_time = 0;
        test_done = uvm_event_pool::get_global("test_done");
        forever begin
            @(posedge probe.clk);
            if(probe.reset) begin
                commit_time = 0;
                continue;
            end
            if(probe.commit) begin
                item = probe_item::type_id::create("item");
                item.rd_addr = probe.rd_addr;
                item.rd_value = probe.rd_data;
                item.pc = probe.pc;
                ap.write(item);
                commit_time = commit_time + 1;
            end
            if(commit_time >= `TEST_TIMES) begin
                test_done.trigger();
                commit_time = 0;
            end
        end
    endtask

endclass
