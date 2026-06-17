class calc_item extends instr_item;

    `uvm_object_utils(calc_item)

    rand logic [6:0] funct7;
    rand logic [4:0] rs2;
    rand logic [4:0] rs1;
    rand logic [2:0] funct3;
    rand logic [4:0] rd;
    rand logic [6:0] opcode;

    constraint instr_c {

        opcode inside {7'b0110011, 7'b0010011};

        if (opcode == 7'b0110011) { // R-type
            
            funct7 inside {7'b0000001, 7'b0100000, 7'b0000000};
            
            if (funct7 == 7'b0000001) {
                funct3 inside {3'b000, 3'b001, 3'b010, 3'b011, 3'b100, 3'b101, 3'b110, 3'b111};
            }
            else if (funct7 == 7'b0100000) {
                funct3 inside {3'b000, 3'b101};
            }
            else if (funct7 == 7'b0000000) {
                funct3 inside {3'b000, 3'b001, 3'b010, 3'b011, 3'b100, 3'b101, 3'b110, 3'b111};
            }

        }
        else if (opcode == 7'b0010011) { // I-type
            
            funct3 inside {[3'b000 : 3'b111]};

            if (funct3 == 3'b001) {
                funct7 == 7'b0000000;
            }
            else if (funct3 == 3'b101) {
                funct7 inside {7'b0000000, 7'b0100000};
            }

        }

        instr == {funct7, rs2, rs1, funct3, rd, opcode};
    }

    function new(string name = "calc_item");
        super.new(name);
    endfunction

endclass
