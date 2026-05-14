class mycore_item extends uvm_sequence_item;
    
    rand bit [31:0] pm_rd;
    rand bit [31:0] dm_rd;
    rand bit        ld_valid;

    `uvm_object_utils_begin(mycore_item)
        `uvm_field_int(pm_rd, UVM_DEFAULT)
        `uvm_field_int(dm_rd, UVM_DEFAULT)
        `uvm_field_int(ld_valid, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "mycore_item");
        super.new(name);
    endfunction

endclass
