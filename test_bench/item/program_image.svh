class program_image extends uvm_object;
    `uvm_object_utils(program_image)


    bit [31:0] PM [int unsigned];
    bit [31:0] linear_instr_q[$];

    function new(string name = "program_image");
        super.new(name);
    endfunction

    virtual function void clear();
        PM.delete();
        linear_instr_q.delete();
    endfunction

    function void put_instr(bit [31:0] pc, bit [31:0] instr);
        PM[pc >> 2] = instr;
        linear_instr_q.push_back(instr);
    endfunction

    function bit [31:0] read_instr(bit [31:0] pc);
        if (PM.exists(pc >> 2)) begin
            return PM[pc >> 2];
        end
        else begin
            return 32'h0000_0013; // ADDI x0, x0, 0，NOP
        end
    endfunction

    function int unsigned instr_count();
        return linear_instr_q.size();
    endfunction

endclass
