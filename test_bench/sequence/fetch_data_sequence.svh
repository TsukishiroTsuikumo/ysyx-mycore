class fetch_data_sequence extends uvm_sequence #(fetch_data_item);

    `uvm_object_utils(fetch_data_sequence)

    function new(string name = "fetch_data_sequence");
        super.new(name);
    endfunction

    virtual task body();
        fetch_data_item item;
        for (int unsigned i = 0; i < `TEST_TIMES; i++) begin
            item = fetch_data_item::type_id::create("item");
            start_item(item);
            if(!item.randomize()) begin
                `uvm_fatal("FETCH_DATA_SEQUENCE", "Failed to randomize fetch_data item");
            end
            finish_item(item);
        end
    endtask

endclass
