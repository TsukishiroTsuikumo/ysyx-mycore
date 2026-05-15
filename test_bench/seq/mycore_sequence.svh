`ifndef TEST_TIMES
`define TEST_TIMES 200
`endif

class mycore_sequence extends uvm_sequence #(mycore_item);
    
    `uvm_object_utils(mycore_sequence)

    int unsigned num_items = `TEST_TIMES;

    function new(string name = "mycore_sequence");
        super.new(name);
    endfunction

    virtual task body();
        mycore_item item;

        repeat(num_items) begin
            item = mycore_item::type_id::create("item");
            start_item(item);
            assert(item.randomize());
            finish_item(item);
        end
    endtask

endclass
