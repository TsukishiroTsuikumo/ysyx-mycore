class st_item extends instr_item;

    `uvm_object_utils(st_item)

    rand logic [11:0] imm;
    rand logic [4:0]  rs2;
    rand logic [4:0]  rs1;
    rand logic [2:0]  funct3;

    constraint instr_c {
        funct3 inside {3'b000, 3'b001, 3'b010};
        rs1 == 5'd0;
        imm inside {[12'h000:12'h07c]};
        imm[1:0] == 2'b00;
        instr == {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'b0100011};
    }

    function new(string name = "st_item");
        super.new(name);
    endfunction

endclass
