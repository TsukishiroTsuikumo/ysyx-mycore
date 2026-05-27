class probe_item extends uvm_sequence_item;

    bit [4:0]   rd_addr;
    bit [31:0]  rd_value;
    bit [31:0]  pc;

    `uvm_object_utils_begin(probe_item)
        `uvm_field_int(rd_addr,    UVM_DEFAULT)
        `uvm_field_int(rd_value,   UVM_DEFAULT)
        `uvm_field_int(pc,         UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "probe_item");
        super.new(name);
    endfunction

endclass
