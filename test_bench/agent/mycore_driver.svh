class mycore_driver extends uvm_driver #(mycore_item);
    `uvm_component_utils(mycore_driver)

    virtual mycore_if vif;
  
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual mycore_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "driver cannot get vif")
    endfunction

    task run_phase(uvm_phase phase);
        mycore_item item;
        forever begin
            seq_item_port.get_next_item(item);
            @(posedge vif.clk);
            vif.pm_rd_in <= item.pm_rd_in;
            vif.dm_rd_in <= item.dm_rd_in;
            vif.ld_valid <= item.ld_valid;
            seq_item_port.item_done();
        end
    endtask

endclass
