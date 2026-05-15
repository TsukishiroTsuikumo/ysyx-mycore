class program_item extends mycore_item;
    `uvm_object_utils(program_item)

    bit [31:0] pm_addr;
    bit        ifetch;
    bit        ins_valid;
    bit [31:0] dm_wr;
    bit [31:0] dm_addr;
    bit [3:0]  dm_st;
    bit [3:0]  dm_ld;

    function new(string name = "program_item");
        super.new(name);
    endfunction

endclass
