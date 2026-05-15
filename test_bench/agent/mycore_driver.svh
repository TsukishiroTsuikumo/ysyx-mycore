class mycore_driver extends uvm_driver #(mycore_item);
    `uvm_component_utils(mycore_driver)

    virtual mycore_if vif;
    virtual state_probe_if probe_vif;
  
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual mycore_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "driver cannot get vif")
        if (!uvm_config_db#(virtual state_probe_if)::get(this, "", "vif", probe_vif))
            `uvm_fatal("NOVIF", "driver cannot get state_probe_if")
    endfunction

    task run_phase(uvm_phase phase);
        mycore_item item;
        forever begin
            seq_item_port.get_next_item(item);
            do begin
                @(negedge vif.clk);
                vif.pm_rd <= item.pm_rd;
                vif.ins_valid <= 1'b1;
                vif.dm_rd <= item.dm_rd;
                vif.ld_valid <= item.ld_valid;
                @(posedge vif.clk);
            end while (probe_vif.reset || !probe_vif.instr_accept);
            seq_item_port.item_done();
        end
    endtask

endclass
