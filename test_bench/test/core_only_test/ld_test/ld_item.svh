class ld_item extends instr_item;

    `uvm_object_utils(ld_item)

    rand logic [11:0] imm;
    rand logic [4:0]  rs1;
    rand logic [2:0]  funct3;
    rand logic [4:0]  rd;

    constraint instr_c {
        funct3 inside {3'b000, 3'b001, 3'b010, 3'b100, 3'b101};
        rd != 5'd0;
        rs1 == 5'd0;
        imm inside {[12'h000:12'h07c]};
        imm[1:0] == 2'b00;
        instr == {imm, rs1, funct3, rd, 7'b0000011};
    }

    function new(string name = "ld_item");
        super.new(name);
    endfunction

endclass
