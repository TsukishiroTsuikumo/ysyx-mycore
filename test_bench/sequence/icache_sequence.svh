class icache_sequence extends uvm_sequence #(icache_item);

    `uvm_object_utils(icache_sequence)

    function new(string name = "icache_sequence");
        super.new(name);
    endfunction

    task body();
        icache_item item;
        item = icache_item::type_id::create("item");
        start_item(item);
        if (!item.randomize()) begin
            `uvm_error("ICACHE_SEQ", "Failed to randomize the request item")
        end
        finish_item(item);
    endtask

endclass
