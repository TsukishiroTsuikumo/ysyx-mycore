class instr_item extends uvm_sequence_item;

    rand bit [31:0] instr;
    
    `uvm_object_utils_begin(instr_item)
        `uvm_field_int(instr, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "instr_item");
        super.new(name);
    endfunction

endclass
