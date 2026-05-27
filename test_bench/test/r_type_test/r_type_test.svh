class r_type_test extends mycore_test;
    `uvm_component_utils(r_type_test)

    function new(string name = "r_type_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        instr_item::type_id::set_type_override(r_type_item::get_type());
        mycore_scoreboard::type_id::set_type_override(r_type_scoreboard::get_type());
        super.build_phase(phase);
    endfunction

endclass
