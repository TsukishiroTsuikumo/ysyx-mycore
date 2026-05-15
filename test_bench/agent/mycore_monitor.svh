class mycore_monitor extends uvm_monitor;
    `uvm_component_utils(mycore_monitor)

    mycore_item item;
    virtual mycore_if vif;
    virtual state_probe_if probe_vif;
    uvm_analysis_port #(mycore_item) act_port;
  
    function new(string name, uvm_component parent);
        super.new(name, parent);
        act_port = new("act_port", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual mycore_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "monitor cannot get vif")
        if (!uvm_config_db#(virtual state_probe_if)::get(this, "", "vif", probe_vif))
            `uvm_fatal("NOVIF", "monitor cannot get state_probe_if")
    endfunction

    virtual task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.clk);
            if (probe_vif.reset) begin
                continue;
            end

            if (probe_vif.instr_accept) begin
                item = mycore_item::type_id::create("item");
                item.pm_rd    = vif.pm_rd;
                item.dm_rd    = vif.dm_rd;
                item.ld_valid = vif.ld_valid;
                act_port.write(item);
            end
        end
    endtask

endclass
