class ldst_image_test extends mem_image_test;
    `uvm_component_utils(ldst_image_test)

    function new(string name = "ldst_image_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function int unsigned get_default_target_commits();
        return 20;
    endfunction

    virtual task pre_reset_setup();
        string mem_arg;

        if (!$value$plusargs("MEM_FILE=%s", mem_arg) &&
            !$value$plusargs("MEM=%s", mem_arg)) begin
            `uvm_fatal("LDST_IMAGE_TEST",
                "ldst_image_test requires +MEM_FILE=<path> or +MEM=<base>")
        end
    endtask

endclass
