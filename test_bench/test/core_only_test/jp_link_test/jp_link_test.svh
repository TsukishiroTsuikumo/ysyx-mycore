class jp_link_test extends instr_base_test;
    `uvm_component_utils(jp_link_test)

    function new(string name = "jp_link_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        instr_item::type_id::set_type_override(jp_link_item::get_type());
        mycore_scoreboard::type_id::set_type_override(jp_link_scoreboard::get_type());
        super.build_phase(phase);
    endfunction

    virtual function int unsigned get_default_target_commits();
        return (`TEST_TIMES / 4);
    endfunction

endclass
