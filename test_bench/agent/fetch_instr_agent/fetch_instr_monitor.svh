class fetch_instr_monitor extends uvm_monitor;
    `uvm_component_utils(fetch_instr_monitor)

    virtual icache_if vif;
    uvm_analysis_port#(instr_item) analysis_port;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        analysis_port = new("analysis_port", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual icache_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("FETCH_INSTR_MONITOR", "Virtual interface not found")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        instr_item item;
        forever begin
            @(posedge vif.clk);
            if(vif.reset) begin
                continue;
            end
            if(vif.resp_valid) begin
                item = instr_item::type_id::create("item");
                item.instr = vif.resp_data;
                analysis_port.write(item);
            end
        end
    endtask

endclass
