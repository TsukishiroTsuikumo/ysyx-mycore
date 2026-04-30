`define TEST_TIME 20

class mycore_sequence extends uvm_sequence #(mycore_item);
    
    `uvm_object_utils(mycore_sequence)

    function new(string name = "mycore_sequence");
        super.new(name);
    endfunction

    virtual task body();
        mycore_item item;

        repeat(`TEST_TIME) begin
            `uvm_info(get_type_name(), $sformatf("Start item %0d", get_automator().get_sequence_item_count()), UVM_LOW)
            item = mycore_item::type_id::create("item");
            start_item(item);
            assert(item.randomize());
            finish_item(item);
        end
    endtask

endclass