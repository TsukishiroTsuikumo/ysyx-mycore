class st_test extends instr_base_test;
    `uvm_component_utils(st_test)

    virtual dcache_if dc_vif;

    function new(string name = "st_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        instr_item::type_id::set_type_override(st_item::get_type());
        mycore_scoreboard::type_id::set_type_override(st_scoreboard::get_type());
        super.build_phase(phase);
        if (!uvm_config_db#(virtual dcache_if)::get(this, "", "vif", dc_vif)) begin
            `uvm_fatal("ST_TEST", "Failed to get dcache interface")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
    endtask

endclass
