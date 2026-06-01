class jp_link_item extends instr_item;

    `uvm_object_utils(jp_link_item)

    rand logic [4:0] rd;

    constraint instr_c {
        rd == 5'd1;
        // JAL rd, +4. This keeps the direct-driver instruction stream
        // sequential while still checking jump/link writeback.
        instr == {1'b0, 10'd2, 1'b0, 8'd0, rd, 7'b1101111};
    }

    function new(string name = "jp_link_item");
        super.new(name);
    endfunction

endclass
