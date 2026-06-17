class program_test extends program_base_test;
    `uvm_component_utils(program_test)

    program_image image;
    program_sequence pg_seq;

    function new(string name = "program_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        instr_item::type_id::set_type_override(calc_item::get_type());
        mycore_scoreboard::type_id::set_type_override(program_scoreboard::get_type());

        image = program_image::type_id::create("image");
        uvm_config_db#(program_image)::set(this, "env.scoreboard", "image", image);

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

        if (!cmodel_init_empty()) begin
            `uvm_fatal("PROGRAM_TEST", "C model failed to initialize")
        end

        foreach (image.PM[word_addr]) begin
            $root.test_bench.dut.u_mem.write_word(word_addr << 2, image.PM[word_addr]);
            cmodel_mem_write32(word_addr << 2, image.PM[word_addr]);
        end

        `uvm_info("PROGRAM_TEST", $sformatf(
            "preloaded %0d generated program words into MEM", image.instr_count()), UVM_LOW)
    endtask

endclass
