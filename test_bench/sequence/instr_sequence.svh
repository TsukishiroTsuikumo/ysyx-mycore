class instr_sequence extends uvm_sequence #(instr_item);
    `uvm_object_utils(instr_sequence)

    function new(string name = "instr_sequence");
        super.new(name);
    endfunction

    virtual task body();
        instr_item item;
        for (int unsigned i = 0; i < `TEST_TIMES; i++) begin
            item = instr_item::type_id::create("item");
            start_item(item);
            if(!item.randomize()) begin
                `uvm_fatal("INSTR_SEQUENCE", "Failed to randomize instruction item");
            end
            finish_item(item);
        end
    endtask

endclass
