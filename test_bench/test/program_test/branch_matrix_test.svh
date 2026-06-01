class branch_matrix_test extends program_base_test;
    `uvm_component_utils(branch_matrix_test)

    function new(string name = "branch_matrix_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        mycore_scoreboard::type_id::set_type_override(branch_matrix_scoreboard::get_type());
        super.build_phase(phase);
    endfunction

    virtual function int unsigned get_default_target_commits();
        return 17;
    endfunction

    virtual task pre_reset_setup();
        string mem_arg;

        if (!$value$plusargs("MEM_FILE=%s", mem_arg) &&
            !$value$plusargs("MEM=%s", mem_arg)) begin
            `uvm_fatal("BRANCH_MATRIX_TEST",
                "branch_matrix_test requires +MEM_FILE=<path> or +MEM=<base>")
        end
    endtask

    virtual task start_main_sequence();
        // MEM loads the branch matrix image from +MEM or +MEM_FILE.
    endtask

endclass
