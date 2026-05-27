class r_type_scoreboard extends mycore_scoreboard;
    `uvm_component_utils(r_type_scoreboard)

    typedef struct packed {
        bit [4:0]  rd;
        bit [31:0] value;
        bit [31:0] instr;
    } reg_write_t;

    reg_write_t exp_q[$];
    reg_write_t act_q[$];
    bit [31:0]  exp_regs[0:31];
    bit         regs_loaded;

    int unsigned pass_count;
    int unsigned fail_count;
    int unsigned missing_count;
    int unsigned extra_count;

    virtual probe_if probe_vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual probe_if)::get(this, "", "probe", probe_vif)) begin
            `uvm_fatal("R_TYPE_SCOREBOARD", "Failed to get probe interface")
        end
    endfunction

    function void load_initial_regs();
        foreach (exp_regs[i]) begin
            exp_regs[i] = probe_vif.init_reg_value[i];
        end
        exp_regs[0] = 32'b0;
        regs_loaded = 1'b1;
    endfunction

    function automatic bit [31:0] calc_r_type(
        input bit [6:0]  funct7,
        input bit [2:0]  funct3,
        input bit [31:0] rs1_val,
        input bit [31:0] rs2_val
    );
        bit [31:0] result;
        bit [4:0] shamt;
        bit signed [32:0] rs1_sx;
        bit signed [32:0] rs2_sx;
        bit signed [32:0] rs2_ux;
        bit signed [65:0] prod_ss;
        bit signed [65:0] prod_su;
        bit [63:0] prod_uu;

        result = 32'b0;
        shamt = rs2_val[4:0];
        rs1_sx = {rs1_val[31], rs1_val};
        rs2_sx = {rs2_val[31], rs2_val};
        rs2_ux = {1'b0, rs2_val};
        prod_ss = rs1_sx * rs2_sx;
        prod_su = rs1_sx * rs2_ux;
        prod_uu = rs1_val * rs2_val;

        case (funct7)
            7'b0000000: begin
                case (funct3)
                    3'b000: result = rs1_val + rs2_val;
                    3'b001: result = rs1_val << shamt;
                    3'b010: result = ($signed(rs1_val) < $signed(rs2_val)) ? 32'd1 : 32'd0;
                    3'b011: result = (rs1_val < rs2_val) ? 32'd1 : 32'd0;
                    3'b100: result = rs1_val ^ rs2_val;
                    3'b101: result = rs1_val >> shamt;
                    3'b110: result = rs1_val | rs2_val;
                    3'b111: result = rs1_val & rs2_val;
                    default: result = 32'b0;
                endcase
            end
            7'b0100000: begin
                case (funct3)
                    3'b000: result = rs1_val - rs2_val;
                    3'b101: result = $signed(rs1_val) >>> shamt;
                    default: result = 32'b0;
                endcase
            end
            7'b0000001: begin
                case (funct3)
                    3'b000: result = rs1_val * rs2_val;
                    3'b001: result = prod_ss[63:32];
                    3'b010: result = prod_su[63:32];
                    3'b011: result = prod_uu[63:32];
                    3'b100: begin
                        if (rs2_val == 0) result = 32'hffff_ffff;
                        else if ((rs1_val == 32'h8000_0000) && (rs2_val == 32'hffff_ffff)) result = 32'h8000_0000;
                        else result = $signed(rs1_val) / $signed(rs2_val);
                    end
                    3'b101: result = (rs2_val == 0) ? 32'hffff_ffff : (rs1_val / rs2_val);
                    3'b110: begin
                        if (rs2_val == 0) result = rs1_val;
                        else if ((rs1_val == 32'h8000_0000) && (rs2_val == 32'hffff_ffff)) result = 32'b0;
                        else result = $signed(rs1_val) % $signed(rs2_val);
                    end
                    3'b111: result = (rs2_val == 0) ? rs1_val : (rs1_val % rs2_val);
                    default: result = 32'b0;
                endcase
            end
            default: result = 32'b0;
        endcase

        return result;
    endfunction

    virtual function void write_instr(instr_item item);
        bit [31:0] instr;
        bit [6:0]  opcode;
        bit [6:0]  funct7;
        bit [2:0]  funct3;
        bit [4:0]  rs1;
        bit [4:0]  rs2;
        bit [4:0]  rd;
        reg_write_t exp;

        super.write_instr(item);
        if (item == null) return;
        if (!regs_loaded) load_initial_regs();

        instr = item.instr;
        opcode = instr[6:0];
        if (opcode != 7'b0110011) return;

        rd = instr[11:7];
        funct3 = instr[14:12];
        rs1 = instr[19:15];
        rs2 = instr[24:20];
        funct7 = instr[31:25];

        exp.rd = rd;
        exp.value = calc_r_type(funct7, funct3, exp_regs[rs1], exp_regs[rs2]);
        exp.instr = instr;
        if (rd == 5'd0) exp.value = 32'b0;

        exp_q.push_back(exp);
        if (rd != 5'd0) exp_regs[rd] = exp.value;
    endfunction

    virtual function void write_commit(probe_item item);
        reg_write_t act;

        super.write_commit(item);
        if (item == null) return;

        act.rd = item.rd_addr;
        act.value = item.rd_value;
        act.instr = 32'b0;
        act_q.push_back(act);
    endfunction

    virtual function void check_phase(uvm_phase phase);
        reg_write_t exp;
        reg_write_t act;

        super.check_phase(phase);

        while ((exp_q.size() != 0) && (act_q.size() != 0)) begin
            exp = exp_q.pop_front();
            act = act_q.pop_front();
            if (act.rd !== exp.rd) begin
                fail_count++;
                `uvm_error("R_TYPE_SCORE", $sformatf(
                    "rd mismatch instr=0x%08x exp=x%0d act=x%0d",
                    exp.instr, exp.rd, act.rd))
            end
            else if ((exp.rd != 5'd0) && (act.value !== exp.value)) begin
                fail_count++;
                `uvm_error("R_TYPE_SCORE", $sformatf(
                    "data mismatch instr=0x%08x rd=x%0d exp=0x%08x act=0x%08x",
                    exp.instr, exp.rd, exp.value, act.value))
            end
            else begin
                pass_count++;
            end
        end

        missing_count = exp_q.size();
        extra_count = act_q.size();

        while (exp_q.size() != 0) begin
            exp = exp_q.pop_front();
            `uvm_error("R_TYPE_SCORE", $sformatf(
                "missing commit instr=0x%08x rd=x%0d exp=0x%08x",
                exp.instr, exp.rd, exp.value))
        end

        while (act_q.size() != 0) begin
            act = act_q.pop_front();
            `uvm_error("R_TYPE_SCORE", $sformatf(
                "unexpected commit rd=x%0d value=0x%08x", act.rd, act.value))
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("R_TYPE_SCORE", $sformatf(
            "pass=%0d fail=%0d missing=%0d extra=%0d",
            pass_count, fail_count, missing_count, extra_count), UVM_NONE)
    endfunction

endclass
