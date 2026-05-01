`define TEST_TIME 20

class mycore_sequence extends uvm_sequence #(mycore_item);
    
    `uvm_object_utils(mycore_sequence)

    function new(string name = "mycore_sequence");
        super.new(name);
    endfunction

    virtual task body();
        mycore_item item;

        repeat(`TEST_TIME) begin
            item = mycore_item::type_id::create("item");
            start_item(item);
            assert(item.randomize());
            finish_item(item);
        end
    endtask

endclass
