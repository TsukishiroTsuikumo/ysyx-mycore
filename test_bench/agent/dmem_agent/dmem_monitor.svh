class dmem_monitor extends uvm_monitor;

    `uvm_component_utils(dmem_monitor)

    virtual dcache_if vif;
    uvm_analysis_port#(dmem_item) analysis_port;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        analysis_port = new("analysis_port", this);
    endfunction

    virtual function void build_phase (uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual dcache_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("DMEM_MONITOR", "Failed to get dcache interface");
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        dmem_item item;
        forever begin
            @(posedge vif.clk);
            if(vif.rst) begin
                continue;
            end
            if(vif.req_rvalid && vif.req_rready) begin
                item = dmem_item::type_id::create("item");
                item.is_read = 1'b1;
                item.addr = vif.req_addr;
                @(posedge vif.clk);
                item.data = vif.resp_rdata;
                analysis_port.write(item);
            end
            if(vif.req_wvalid && vif.req_wready) begin
                item = dmem_item::type_id::create("item");
                item.is_write = 1'b1;
                item.addr = vif.req_addr;
                item.wstrb = vif.req_wstrb;
                item.wdata = vif.req_wdata;
                analysis_port.write(item);
            end
        end
    endtask

endclass
