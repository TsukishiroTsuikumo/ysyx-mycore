class mem_image_test extends program_base_test;
    `uvm_component_utils(mem_image_test)

    function new(string name = "mem_image_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        mycore_scoreboard::type_id::set_type_override(program_scoreboard::get_type());
        super.build_phase(phase);
    endfunction

endclass
