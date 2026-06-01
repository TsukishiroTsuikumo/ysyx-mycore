`define TEST_TIMES 200

class program_sequence extends uvm_sequence #(instr_item);
    `uvm_object_utils(program_sequence)

    program_image image;

    function new(string name = "program_sequence");
        super.new(name);
    endfunction

    virtual task body();
        instr_item item;

        if (image == null) begin
            image = program_image::type_id::create("image");
        end
        image.clear();

        for (int unsigned i = 0; i < `TEST_TIMES; i++) begin
            item = instr_item::type_id::create("item");
            if(!item.randomize()) begin
                `uvm_fatal("PROGRAM_SEQUENCE", "Failed to randomize instruction item");
            end
            image.put_instr(i * 4, item.instr);
        end
        
        if(image.instr_count() == 0) begin
            image.put_instr(32'h0000_0000, 32'h00000013);
            `uvm_info("PROGRAM_SEQUENCE", $sformatf(
                "NO PROGRAM IMAGE INITIALIZES"), UVM_HIGH)
        end

    endtask

endclass
