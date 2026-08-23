class isa_coverage extends uvm_subscriber #(probe_item);
    `uvm_component_utils(isa_coverage)

    localparam int unsigned INSTRUCTION_BIN_COUNT = 45;
    localparam int unsigned BRANCH_BIN_COUNT = 12;
    localparam int unsigned REQUIRED_BIN_COUNT =
        INSTRUCTION_BIN_COUNT + BRANCH_BIN_COUNT;

    bit [REQUIRED_BIN_COUNT-1:0] hit_bins;
    bit require_complete;
    bit pending_branch;
    bit [31:0] pending_branch_pc;
    bit [31:0] pending_branch_instr;

    function new(string name = "isa_coverage", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        require_complete = $test$plusargs("REQUIRE_ISA_COVERAGE");
    endfunction

    function automatic int instruction_bin(input bit [31:0] instr);
        bit [6:0] opcode;
        bit [2:0] funct3;
        bit [6:0] funct7;
        opcode = instr[6:0];
        funct3 = instr[14:12];
        funct7 = instr[31:25];

        case (opcode)
            7'b0110111: return 0;  // LUI
            7'b0010111: return 1;  // AUIPC
            7'b1101111: return 2;  // JAL
            7'b1100111: return (funct3 == 3'b000) ? 3 : -1; // JALR
            7'b1100011: begin
                case (funct3)
                    3'b000: return 4; // BEQ
                    3'b001: return 5; // BNE
                    3'b100: return 6; // BLT
                    3'b101: return 7; // BGE
                    3'b110: return 8; // BLTU
                    3'b111: return 9; // BGEU
                    default: return -1;
                endcase
            end
            7'b0000011: begin
                case (funct3)
                    3'b000: return 10; // LB
                    3'b001: return 11; // LH
                    3'b010: return 12; // LW
                    3'b100: return 13; // LBU
                    3'b101: return 14; // LHU
                    default: return -1;
                endcase
            end
            7'b0100011: begin
                case (funct3)
                    3'b000: return 15; // SB
                    3'b001: return 16; // SH
                    3'b010: return 17; // SW
                    default: return -1;
                endcase
            end
            7'b0010011: begin
                case (funct3)
                    3'b000: return 18; // ADDI
                    3'b010: return 19; // SLTI
                    3'b011: return 20; // SLTIU
                    3'b100: return 21; // XORI
                    3'b110: return 22; // ORI
                    3'b111: return 23; // ANDI
                    3'b001: return (funct7 == 7'b0000000) ? 24 : -1; // SLLI
                    3'b101: begin
                        if (funct7 == 7'b0000000) return 25; // SRLI
                        if (funct7 == 7'b0100000) return 26; // SRAI
                        return -1;
                    end
                    default: return -1;
                endcase
            end
            7'b0110011: begin
                if (funct7 == 7'b0000001) begin
                    case (funct3)
                        3'b000: return 37; // MUL
                        3'b001: return 38; // MULH
                        3'b010: return 39; // MULHSU
                        3'b011: return 40; // MULHU
                        3'b100: return 41; // DIV
                        3'b101: return 42; // DIVU
                        3'b110: return 43; // REM
                        3'b111: return 44; // REMU
                    endcase
                end
                else begin
                    case (funct3)
                        3'b000: begin
                            if (funct7 == 7'b0000000) return 27; // ADD
                            if (funct7 == 7'b0100000) return 28; // SUB
                            return -1;
                        end
                        3'b001: return (funct7 == 7'b0000000) ? 29 : -1; // SLL
                        3'b010: return (funct7 == 7'b0000000) ? 30 : -1; // SLT
                        3'b011: return (funct7 == 7'b0000000) ? 31 : -1; // SLTU
                        3'b100: return (funct7 == 7'b0000000) ? 32 : -1; // XOR
                        3'b101: begin
                            if (funct7 == 7'b0000000) return 33; // SRL
                            if (funct7 == 7'b0100000) return 34; // SRA
                            return -1;
                        end
                        3'b110: return (funct7 == 7'b0000000) ? 35 : -1; // OR
                        3'b111: return (funct7 == 7'b0000000) ? 36 : -1; // AND
                    endcase
                end
                return -1;
            end
            default: return -1;
        endcase
    endfunction

    function automatic int branch_kind(input bit [31:0] instr);
        if (instr[6:0] != 7'b1100011) return -1;
        case (instr[14:12])
            3'b000: return 0; // BEQ
            3'b001: return 1; // BNE
            3'b100: return 2; // BLT
            3'b101: return 3; // BGE
            3'b110: return 4; // BLTU
            3'b111: return 5; // BGEU
            default: return -1;
        endcase
    endfunction

    function automatic string bin_name(input int index);
        case (index)
            0: return "LUI";
            1: return "AUIPC";
            2: return "JAL";
            3: return "JALR";
            4: return "BEQ";
            5: return "BNE";
            6: return "BLT";
            7: return "BGE";
            8: return "BLTU";
            9: return "BGEU";
            10: return "LB";
            11: return "LH";
            12: return "LW";
            13: return "LBU";
            14: return "LHU";
            15: return "SB";
            16: return "SH";
            17: return "SW";
            18: return "ADDI";
            19: return "SLTI";
            20: return "SLTIU";
            21: return "XORI";
            22: return "ORI";
            23: return "ANDI";
            24: return "SLLI";
            25: return "SRLI";
            26: return "SRAI";
            27: return "ADD";
            28: return "SUB";
            29: return "SLL";
            30: return "SLT";
            31: return "SLTU";
            32: return "XOR";
            33: return "SRL";
            34: return "SRA";
            35: return "OR";
            36: return "AND";
            37: return "MUL";
            38: return "MULH";
            39: return "MULHSU";
            40: return "MULHU";
            41: return "DIV";
            42: return "DIVU";
            43: return "REM";
            44: return "REMU";
            45: return "BEQ_NOT_TAKEN";
            46: return "BEQ_TAKEN";
            47: return "BNE_NOT_TAKEN";
            48: return "BNE_TAKEN";
            49: return "BLT_NOT_TAKEN";
            50: return "BLT_TAKEN";
            51: return "BGE_NOT_TAKEN";
            52: return "BGE_TAKEN";
            53: return "BLTU_NOT_TAKEN";
            54: return "BLTU_TAKEN";
            55: return "BGEU_NOT_TAKEN";
            56: return "BGEU_TAKEN";
            default: return "UNKNOWN";
        endcase
    endfunction

    virtual function void write(probe_item item);
        int index;
        int kind;
        bit taken;

        if ((item == null) || !item.retire) return;

        if (pending_branch) begin
            kind = branch_kind(pending_branch_instr);
            taken = (item.pc != (pending_branch_pc + 32'd4));
            if (kind >= 0)
                hit_bins[INSTRUCTION_BIN_COUNT + (kind * 2) + taken] = 1'b1;
        end

        index = instruction_bin(item.instr);
        if (index >= 0) hit_bins[index] = 1'b1;

        kind = branch_kind(item.instr);
        pending_branch = (kind >= 0);
        if (kind >= 0) begin
            pending_branch_pc = item.pc;
            pending_branch_instr = item.instr;
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        int hit_count;
        int instruction_hits;
        int branch_hits;
        string missing_bins;
        string status;

        super.report_phase(phase);
        hit_count = 0;
        instruction_hits = 0;
        branch_hits = 0;
        missing_bins = "";
        for (int index = 0; index < REQUIRED_BIN_COUNT; index++) begin
            if (hit_bins[index]) begin
                hit_count++;
                if (index < INSTRUCTION_BIN_COUNT)
                    instruction_hits++;
                else
                    branch_hits++;
            end
            else begin
                if (missing_bins.len() != 0) missing_bins = {missing_bins, ","};
                missing_bins = {missing_bins, bin_name(index)};
            end
        end

        if (hit_count == REQUIRED_BIN_COUNT)
            status = "PASS";
        else if (require_complete)
            status = "FAIL";
        else
            status = "INCOMPLETE";

        `uvm_info("ISA_COVERAGE", $sformatf(
            "ISA_COVERAGE status=%s required=%0d hit=%0d missing=%0d instr=%0d/%0d branch=%0d/%0d missing_bins=%s",
            status, REQUIRED_BIN_COUNT, hit_count,
            REQUIRED_BIN_COUNT - hit_count, instruction_hits,
            INSTRUCTION_BIN_COUNT, branch_hits, BRANCH_BIN_COUNT,
            (missing_bins.len() == 0) ? "none" : missing_bins), UVM_NONE)

        if (require_complete && (hit_count != REQUIRED_BIN_COUNT)) begin
            `uvm_error("ISA_COVERAGE", $sformatf(
                "required ISA coverage bins are missing: %s", missing_bins))
        end
    endfunction

endclass
