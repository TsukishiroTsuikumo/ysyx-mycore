class dmem_sequence extends uvm_sequence #(dmem_item);

    `uvm_object_utils(dmem_sequence)

    function new(string name = "dmem_sequence");
        super.new(name);
    endfunction

    virtual task body();
        dmem_item item;
        for (int unsigned i = 0; i < `TEST_TIMES; i++) begin
            item = dmem_item::type_id::create("item");
            start_item(item);
            if(!item.randomize()) begin
                `uvm_fatal("DMEM_SEQUENCE", "Failed to randomize dmem item");
            end
            finish_item(item);
        end
    endtask

endclass
