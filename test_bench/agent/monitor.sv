class mycore_monitor extend uvm_monitor;
    `uvm_component_utils(mycore_monitor)

    virtual mycore_if vif;
    uvm_analysis_port #(mycore_item) act_port;
  
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
    endfunction

    virtual task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.clk);
            mycore_item item = mycore_item::type_id::create("item");
            item.pm_rd_in = vif.pm_rd_in;
            item.dm_rd_in = vif.dm_rd_in;
            item.ld_valid = vif.ld_valid;
            act_port.write(item);
        end
    endtask

endclass