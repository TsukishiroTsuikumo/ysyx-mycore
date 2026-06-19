class fetch_data_monitor extends uvm_monitor;

    `uvm_component_utils(fetch_data_monitor)

    virtual dcache_if vif;
    uvm_analysis_port#(fetch_data_item) analysis_port;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        analysis_port = new("analysis_port", this);
    endfunction

    virtual function void build_phase (uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual dcache_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("FETCH_DATA_MONITOR", "Failed to get dcache interface");
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        fetch_data_item item;
        fetch_data_item read_q[$];
        forever begin
            @(posedge vif.clk);
            if(vif.reset) begin
                read_q.delete();
                continue;
            end
            if(vif.req_rvalid && vif.req_rready) begin
                item = fetch_data_item::type_id::create("item");
                item.is_read = 1'b1;
                item.addr = vif.req_addr;
                read_q.push_back(item);
            end
            if(vif.resp_rvalid) begin
                if (read_q.size() == 0) begin
                    `uvm_error("FETCH_DATA_MONITOR", "Read response without pending read request")
                end
                else begin
                    item = read_q.pop_front();
                    item.rdata = vif.resp_rdata;
                    analysis_port.write(item);
                end
            end
            if(vif.req_wvalid && vif.req_wready) begin
                item = fetch_data_item::type_id::create("item");
                item.is_write = 1'b1;
                item.addr = vif.req_addr;
                item.wstrb = vif.req_wstrb;
                item.wdata = vif.req_wdata;
                analysis_port.write(item);
            end
        end
    endtask

endclass
