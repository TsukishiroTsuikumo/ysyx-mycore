class dcache_item extends uvm_sequence_item;

    rand bit        is_read;
    rand bit        is_write;
    rand bit [31:0] addr;
    rand bit [3:0]  wstrb;
    rand bit [31:0] wdata;
    bit      [31:0] rdata;

    constraint kind_c {
        is_read != is_write;
    }

    `uvm_object_utils_begin(dcache_item)
        `uvm_field_int(is_read,  UVM_DEFAULT)
        `uvm_field_int(is_write, UVM_DEFAULT)
        `uvm_field_int(addr,     UVM_DEFAULT)
        `uvm_field_int(wstrb,    UVM_DEFAULT)
        `uvm_field_int(wdata,    UVM_DEFAULT)
        `uvm_field_int(rdata,    UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "dcache_item");
        super.new(name);
    endfunction

endclass
