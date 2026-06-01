class icache_monitor extends uvm_monitor;
    `uvm_component_utils(icache_monitor)

    virtual icache_if vif;
    uvm_analysis_port #(icache_item) analysis_port;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        analysis_port = new("analysis_port", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual icache_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("ICACHE_MONITOR", "Virtual interface not found")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        icache_item item;

        forever begin
            @(posedge vif.clk);
            if (vif.rst) begin
                continue;
            end

            if ((vif.req_valid && vif.req_ready) || vif.resp_valid) begin
                item = icache_item::type_id::create("item");
                item.address = vif.req_addr;
                item.req_valid = vif.req_valid;
                item.req_ready = vif.req_ready;
                item.resp_valid = vif.resp_valid;
                item.resp_data = vif.resp_data;
                analysis_port.write(item);
            end
        end
    endtask

endclass
