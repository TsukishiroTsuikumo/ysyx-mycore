class ld_test extends instr_base_test;
    `uvm_component_utils(ld_test)

    fetch_data_sequence data_seq;

    function new(string name = "ld_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        instr_item::type_id::set_type_override(ld_item::get_type());
        mycore_scoreboard::type_id::set_type_override(program_scoreboard::get_type());
        super.build_phase(phase);
    endfunction

    virtual task start_main_sequence();
        super.start_main_sequence();
        data_seq = fetch_data_sequence::type_id::create("data_seq");
        fork
            data_seq.start(env.data_agent.sequencer);
        join_none
    endtask

endclass
