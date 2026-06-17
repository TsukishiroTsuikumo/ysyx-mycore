class calc_test extends instr_base_test;
    `uvm_component_utils(calc_test)

    function new(string name = "calc_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        instr_item::type_id::set_type_override(calc_item::get_type());
        mycore_scoreboard::type_id::set_type_override(calc_scoreboard::get_type());
        super.build_phase(phase);
    endfunction

endclass
