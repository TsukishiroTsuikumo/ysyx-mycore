class r_type_item extends mycore_item;

    `uvm_object_utils(r_type_item)

    rand logic [6:0] funct7;
    rand logic [4:0] rs2;
    rand logic [4:0] rs1;
    rand logic [2:0] funct3;
    rand logic [4:0] rd;
    rand logic [6:0] opcode;

    constraint instr_c {

        opcode == 7'b0110011;

        funct7 inside {7'b0000001, 7'b0100000, 7'b0000000};

        if (funct7 == 7'b0000001) {
            funct3 inside {3'b000, 3'b001, 3'b010, 3'b011, 3'b100, 3'b101, 3'b110, 3'b111};
        }
        else if (funct7 == 7'b0100000) {
            funct3 inside {3'b000, 3'b101};
        }
        else if (funct7 == 7'b0000000) {
            funct3 inside {3'b000, 3'b111, 3'b110, 3'b100, 3'b011, 3'b101};
        }

        pm_rd == {funct7, rs2, rs1, funct3, rd, opcode};
    }

    function new(string name = "r_type_item");
        super.new(name);
    endfunction

endclass
