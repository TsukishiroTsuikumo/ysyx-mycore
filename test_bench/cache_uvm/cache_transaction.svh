`ifndef YSYX_CACHE_TRANSACTION_SVH
`define YSYX_CACHE_TRANSACTION_SVH

class cache_transaction extends uvm_sequence_item;
    localparam int unsigned IC_READ     = 0;
    localparam int unsigned DC_READ     = 1;
    localparam int unsigned DC_WRITE    = 2;
    localparam int unsigned CACHE_RESET = 3;
    localparam int unsigned IC_FLUSH    = 4;
    localparam int unsigned ID_CONCURRENT_READ = 5;
    localparam int unsigned IC_FLUSH_INFLIGHT = 6;

    bit [2:0]  op;
    bit [31:0] addr;
    bit [31:0] addr2;
    bit [3:0]  wstrb;
    bit [31:0] wdata;
    bit [31:0] rdata;
    bit [127:0] rline;
    int unsigned latency;
    int unsigned mem_read_count;
    int unsigned mem_write_count;
    bit          fault;
    bit          fault_is_writeback;
    bit [1:0]    response_code;

    `uvm_object_utils_begin(cache_transaction)
        `uvm_field_int(op, UVM_DEFAULT)
        `uvm_field_int(addr, UVM_HEX)
        `uvm_field_int(addr2, UVM_HEX)
        `uvm_field_int(wstrb, UVM_HEX)
        `uvm_field_int(wdata, UVM_HEX)
        `uvm_field_int(rdata, UVM_HEX)
        `uvm_field_int(rline, UVM_HEX)
        `uvm_field_int(latency, UVM_DEFAULT)
        `uvm_field_int(mem_read_count, UVM_DEFAULT)
        `uvm_field_int(mem_write_count, UVM_DEFAULT)
        `uvm_field_int(fault, UVM_DEFAULT)
        `uvm_field_int(fault_is_writeback, UVM_DEFAULT)
        `uvm_field_int(response_code, UVM_HEX)
    `uvm_object_utils_end

    function new(string name = "cache_transaction");
        super.new(name);
    endfunction
endclass

`endif
