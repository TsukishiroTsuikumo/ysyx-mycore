`define TEST_TIMES 200

class program_sequence extends uvm_sequence #(instr_item);
    `uvm_object_utils(program_sequence)

    program_image image;

    function new(string name = "program_sequence");
        super.new(name);
    endfunction

    virtual task body();
        instr_item item;

        image = program_image::type_id::create("image");
        image.clear();
        
        for (int unsigned i = 0; i < `TEST_TIMES; i++) begin
            item = instr_item::type_id::create("item");
            if(!item.randomize()) begin
                `uvm_fatal("PROGRAM_SEQUENCE", "Failed to randomize instruction item");
            end
            image.put_instr(i * 4, item.instr);
        end

    endtask

endclass
