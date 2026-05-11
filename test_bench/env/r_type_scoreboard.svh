class r_type_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(r_type_scoreboard)

    uvm_analysis_imp #(mycore_item, r_type_scoreboard) instr_imp;
    virtual state_probe_if probe_vif;

    typedef struct packed {
        logic [4:0]  rd;
        logic [31:0] value;
    } exp_write_t;

    exp_write_t exp_q[$];
    logic [31:0] exp_regs[0:31];
    int unsigned pass_count;
    int unsigned fail_count;
    int unsigned empty_count;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        instr_imp = new("instr_imp", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual state_probe_if)::get(this, "", "vif", probe_vif))
            `uvm_fatal("NOVIF", "scoreboard cannot get state_probe_if")
        foreach (exp_regs[i]) exp_regs[i] = 32'b0;
        pass_count = 0;
        fail_count = 0;
        empty_count = 0;
    endfunction

    function automatic logic [31:0] calc_r_type(
        input logic [6:0] funct7,
        input logic [2:0] funct3,
        input logic [31:0] rs1_val,
        input logic [31:0] rs2_val
    );
        logic [31:0] result;
        logic [4:0] shamt;
        longint signed   prod_ss;
        longint unsigned prod_uu;
        longint signed   prod_su;

        result = 32'b0;
        shamt = rs2_val[4:0];

        case (funct7)
            7'b0000000: begin
                case (funct3)
                    3'b000: result = rs1_val + rs2_val;
                    3'b111: result = rs1_val & rs2_val;
                    3'b110: result = rs1_val | rs2_val;
                    3'b100: result = rs1_val ^ rs2_val;
                    3'b001: result = rs1_val << shamt;
                    3'b101: result = rs1_val >> shamt;
                    default: result = 32'b0;
                endcase
            end
            7'b0100000: begin
                if (funct3 == 3'b000) result = rs1_val - rs2_val;
                else if (funct3 == 3'b101) result = $signed(rs1_val) >>> shamt;
                else result = 32'b0;
            end
            7'b0000001: begin
                case (funct3)
                    3'b000: result = rs1_val * rs2_val;
                    3'b001: begin
                        prod_ss = $signed(rs1_val) * $signed(rs2_val);
                        result = prod_ss[63:32];
                    end
                    3'b010: begin
                        prod_su = $signed(rs1_val) * $unsigned(rs2_val);
                        result = prod_su[63:32];
                    end
                    3'b011: begin
                        prod_uu = $unsigned(rs1_val) * $unsigned(rs2_val);
                        result = prod_uu[63:32];
                    end
                    3'b100: result = (rs2_val == 0) ? 32'hFFFF_FFFF : $signed(rs1_val) / $signed(rs2_val);
                    3'b101: result = (rs2_val == 0) ? 32'hFFFF_FFFF : $unsigned(rs1_val) / $unsigned(rs2_val);
                    3'b110: result = (rs2_val == 0) ? rs1_val : $signed(rs1_val) % $signed(rs2_val);
                    3'b111: result = (rs2_val == 0) ? rs1_val : $unsigned(rs1_val) % $unsigned(rs2_val);
                    default: result = 32'b0;
                endcase
            end
            default: result = 32'b0;
        endcase

        return result;
    endfunction

    function void write(mycore_item item);
        logic [31:0] instr;
        logic [6:0] opcode, funct7;
        logic [2:0] funct3;
        logic [4:0] rs1, rs2, rd;
        exp_write_t exp;

        if (item == null) return;
        instr = item.pm_rd_in;
        opcode = instr[6:0];
        if (opcode != 7'b0110011) return;

        rd = instr[11:7];
        funct3 = instr[14:12];
        rs1 = instr[19:15];
        rs2 = instr[24:20];
        funct7 = instr[31:25];

        exp.rd = rd;
        exp.value = calc_r_type(funct7, funct3, exp_regs[rs1], exp_regs[rs2]);
        if (rd == 5'd0) begin
            exp.value = 32'b0;
        end
        exp_q.push_back(exp);
    endfunction

    task run_phase(uvm_phase phase);
        exp_write_t exp;
        forever begin
            @(posedge probe_vif.clk);
            uvm_wait_for_nba_region();
            if (probe_vif.reset) begin
                exp_q.delete();
                foreach (exp_regs[i]) exp_regs[i] = 32'b0;
                continue;
            end
            if (probe_vif.w1_en) begin
                if (exp_q.size() == 0) begin
                    empty_count++;
                    if (uvm_report_enabled(UVM_NONE, UVM_ERROR, "SCORE") != 0) begin
                        uvm_report_error("SCORE", "writeback seen but expected queue is empty", UVM_NONE);
                    end
                end
                else begin
                    exp = exp_q.pop_front();
                    if (probe_vif.reg_val[exp.rd] !== exp.value) begin
                        fail_count++;
                        if (uvm_report_enabled(UVM_NONE, UVM_ERROR, "SCORE") != 0) begin
                            uvm_report_error("SCORE", $sformatf(
                                "rd x%0d exp=0x%08x act=0x%08x",
                                exp.rd, exp.value, probe_vif.reg_val[exp.rd]
                            ), UVM_NONE);
                        end
                    end else begin
                        pass_count++;
                    end
                    exp_regs[exp.rd] = exp.value;
                end
            end
        end
    endtask

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        if (uvm_report_enabled(UVM_NONE, UVM_INFO, "SCORE") != 0) begin
            uvm_report_info("SCORE", $sformatf(
                "scoreboard summary: pass=%0d fail=%0d empty=%0d",
                pass_count, fail_count, empty_count
            ), UVM_NONE);
        end
    endfunction
endclass
