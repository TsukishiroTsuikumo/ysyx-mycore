class program_test extends mycore_test;
    `uvm_component_utils(program_test)

    program_image image;
    program_sequence pg_seq;

    function new(string name = "program_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        instr_item::type_id::set_type_override(r_type_item::get_type());
        fetch_instr_driver::type_id::set_type_override(program_responder::get_type());
        mycore_scoreboard::type_id::set_type_override(program_scoreboard::get_type());

        image = program_image::type_id::create("image");
        uvm_config_db#(program_image)::set(this, "env.if_agent.driver", "image", image);

        super.build_phase(phase);
    endfunction

    virtual function int unsigned get_default_target_commits();
        int unsigned count;
        count = image.instr_count();
        return (count == 0) ? 1 : count;
    endfunction

    virtual task pre_reset_setup();
        pg_seq = program_sequence::type_id::create("pg_seq");
        pg_seq.image = image;
        pg_seq.start(null);
    endtask

    virtual task start_main_sequence();
        // Program fetch is address-based; program_responder reads program_image
        // directly, so no instruction sequence is started for this test.
    endtask

endclass
