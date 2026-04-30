class mycore_item extend uvm_sequence_item;
    
    rand bit [31:0] pm_rd_in;
    rand bit [31:0] dm_rd_in;
    rand bit        ld_valid;

    `uvm_object_utils_begin(mycore_item)
        `uvm_object_utils_field(pm_rd_in)
        `uvm_object_utils_field(dm_rd_in)
        `uvm_object_utils_field(ld_valid)
    `uvm_object_utils_end

    function new(string name = "mycore_item");
        super.new(name);
    endfunction

endclass