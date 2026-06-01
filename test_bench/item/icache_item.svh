class icache_item extends uvm_sequence_item;

    rand bit [31:0] address;
    rand bit        req_valid;
    rand bit        req_ready;
    rand bit        resp_valid;
    rand bit [31:0] resp_data;

    `uvm_object_utils_begin(icache_item)
        `uvm_field_int(address,    UVM_DEFAULT)
        `uvm_field_int(req_valid,  UVM_DEFAULT)
        `uvm_field_int(req_ready,  UVM_DEFAULT)
        `uvm_field_int(resp_valid, UVM_DEFAULT)
        `uvm_field_int(resp_data,  UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "icache_item");
        super.new(name);
    endfunction

endclass
