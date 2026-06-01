class fetch_data_item extends uvm_sequence_item;

    rand bit [31:0] data;
    bit             is_read;
    bit             is_write;
    bit [31:0]      addr;
    bit [3:0]       wstrb;
    bit [31:0]      wdata;

    `uvm_object_utils_begin(fetch_data_item)
        `uvm_field_int(data,     UVM_DEFAULT)
        `uvm_field_int(is_read,  UVM_DEFAULT)
        `uvm_field_int(is_write, UVM_DEFAULT)
        `uvm_field_int(addr,     UVM_DEFAULT)
        `uvm_field_int(wstrb,    UVM_DEFAULT)
        `uvm_field_int(wdata,    UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "fetch_data_item");
        super.new(name);
    endfunction

endclass
