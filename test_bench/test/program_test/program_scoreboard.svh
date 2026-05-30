class program_scoreboard extends mycore_scoreboard;
    `uvm_component_utils(program_scoreboard)

    typedef struct packed {
        bit [4:0]  rd;
        bit [31:0] value;
        bit [31:0] instr;
        bit [31:0] pc;
    } reg_write_t;

    typedef struct packed {
        bit        is_read;
        bit        is_write;
        bit [31:0] addr;
        bit [3:0]  wstrb;
        bit [31:0] data;
        bit [31:0] wdata;
    } dmem_trace_t;

    virtual probe_if probe_vif;

    bit [31:0] instr_q[$];
    dmem_trace_t dmem_q[$];
    reg_write_t exp_q[$];
    reg_write_t act_q[$];
    bit [31:0] exp_regs[0:31];
    bit        regs_loaded;

    int unsigned pass_count;
    int unsigned fail_count;
    int unsigned missing_count;
    int unsigned extra_count;
    int unsigned dmem_check_count;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual probe_if)::get(this, "", "probe", probe_vif)) begin
            `uvm_fatal("PROGRAM_SCOREBOARD", "Failed to get probe interface")
        end
    endfunction

    function void load_initial_regs();
        foreach (exp_regs[i]) begin
            exp_regs[i] = probe_vif.init_reg_value[i];
        end
        exp_regs[0] = 32'b0;
        regs_loaded = 1'b1;
    endfunction

    function automatic bit [31:0] sext(input bit [31:0] value, input int unsigned width);
        bit [31:0] mask;
        begin
            if (width >= 32) begin
                return value;
            end
            mask = (32'h0000_0001 << width) - 1;
            if (value[width - 1]) begin
                return value | ~mask;
            end
            return value & mask;
        end
    endfunction

    function automatic bit [31:0] calc_r_type(input bit [31:0] instr);
        bit [6:0] funct7;
        bit [2:0] funct3;
        bit [4:0] rs1;
        bit [4:0] rs2;
        bit [31:0] rs1_val;
        bit [31:0] rs2_val;
        bit [4:0] shamt;
        bit signed [32:0] rs1_sx;
        bit signed [32:0] rs2_sx;
        bit signed [32:0] rs2_ux;
        bit signed [65:0] prod_ss;
        bit signed [65:0] prod_su;
        bit [63:0] prod_uu;

        funct7 = instr[31:25];
        rs2 = instr[24:20];
        rs1 = instr[19:15];
        funct3 = instr[14:12];
        rs1_val = exp_regs[rs1];
        rs2_val = exp_regs[rs2];
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
                    3'b000: return rs1_val + rs2_val;
                    3'b001: return rs1_val << shamt;
                    3'b010: return ($signed(rs1_val) < $signed(rs2_val)) ? 32'd1 : 32'd0;
                    3'b011: return (rs1_val < rs2_val) ? 32'd1 : 32'd0;
                    3'b100: return rs1_val ^ rs2_val;
                    3'b101: return rs1_val >> shamt;
                    3'b110: return rs1_val | rs2_val;
                    3'b111: return rs1_val & rs2_val;
                    default: return 32'b0;
                endcase
            end
            7'b0100000: begin
                case (funct3)
                    3'b000: return rs1_val - rs2_val;
                    3'b101: return $signed(rs1_val) >>> shamt;
                    default: return 32'b0;
                endcase
            end
            7'b0000001: begin
                case (funct3)
                    3'b000: return rs1_val * rs2_val;
                    3'b001: return prod_ss[63:32];
                    3'b010: return prod_su[63:32];
                    3'b011: return prod_uu[63:32];
                    3'b100: begin
                        if (rs2_val == 0) return 32'hffff_ffff;
                        if ((rs1_val == 32'h8000_0000) && (rs2_val == 32'hffff_ffff)) return 32'h8000_0000;
                        return $signed(rs1_val) / $signed(rs2_val);
                    end
                    3'b101: return (rs2_val == 0) ? 32'hffff_ffff : (rs1_val / rs2_val);
                    3'b110: begin
                        if (rs2_val == 0) return rs1_val;
                        if ((rs1_val == 32'h8000_0000) && (rs2_val == 32'hffff_ffff)) return 32'b0;
                        return $signed(rs1_val) % $signed(rs2_val);
                    end
                    3'b111: return (rs2_val == 0) ? rs1_val : (rs1_val % rs2_val);
                    default: return 32'b0;
                endcase
            end
            default: return 32'b0;
        endcase
    endfunction

    function automatic bit [31:0] calc_i_type(input bit [31:0] instr);
        bit [2:0] funct3;
        bit [6:0] funct7;
        bit [4:0] rs1;
        bit [31:0] rs1_val;
        bit [31:0] imm;

        funct7 = instr[31:25];
        funct3 = instr[14:12];
        rs1 = instr[19:15];
        rs1_val = exp_regs[rs1];
        imm = sext({20'b0, instr[31:20]}, 12);

        case (funct3)
            3'b000: return rs1_val + imm;
            3'b001: return rs1_val << instr[24:20];
            3'b010: return ($signed(rs1_val) < $signed(imm)) ? 32'd1 : 32'd0;
            3'b011: return (rs1_val < imm) ? 32'd1 : 32'd0;
            3'b100: return rs1_val ^ imm;
            3'b101: begin
                if (funct7 == 7'b0100000) return $signed(rs1_val) >>> instr[24:20];
                return rs1_val >> instr[24:20];
            end
            3'b110: return rs1_val | imm;
            3'b111: return rs1_val & imm;
            default: return 32'b0;
        endcase
    endfunction

    function automatic bit branch_taken(input bit [31:0] instr);
        bit [2:0] funct3;
        bit [4:0] rs1;
        bit [4:0] rs2;
        bit [31:0] rs1_val;
        bit [31:0] rs2_val;

        funct3 = instr[14:12];
        rs1 = instr[19:15];
        rs2 = instr[24:20];
        rs1_val = exp_regs[rs1];
        rs2_val = exp_regs[rs2];

        case (funct3)
            3'b000: return (rs1_val == rs2_val);
            3'b001: return (rs1_val != rs2_val);
            3'b100: return ($signed(rs1_val) < $signed(rs2_val));
            3'b101: return ($signed(rs1_val) >= $signed(rs2_val));
            3'b110: return (rs1_val < rs2_val);
            3'b111: return (rs1_val >= rs2_val);
            default: return 1'b0;
        endcase
    endfunction

    function automatic bit [31:0] load_value(input bit [31:0] instr, input bit [31:0] raw_data);
        case (instr[14:12])
            3'b000: return {{24{raw_data[7]}}, raw_data[7:0]};
            3'b001: return {{16{raw_data[15]}}, raw_data[15:0]};
            3'b010: return raw_data;
            3'b100: return {24'b0, raw_data[7:0]};
            3'b101: return {16'b0, raw_data[15:0]};
            default: return 32'b0;
        endcase
    endfunction

    function automatic bit [3:0] store_wstrb(input bit [31:0] instr);
        case (instr[14:12])
            3'b000: return 4'b0001;
            3'b001: return 4'b0011;
            3'b010: return 4'b1111;
            default: return 4'b0000;
        endcase
    endfunction

    function void push_expected(
        input bit [31:0] instr,
        input bit [31:0] pc,
        input bit [4:0] rd,
        input bit [31:0] value
    );
        reg_write_t exp;

        exp.rd = rd;
        exp.value = (rd == 5'd0) ? 32'b0 : value;
        exp.instr = instr;
        exp.pc = pc;
        exp_q.push_back(exp);
        if (rd != 5'd0) begin
            exp_regs[rd] = exp.value;
        end
    endfunction

    function void check_dmem_read(input bit [31:0] instr, input bit [31:0] addr, output bit [31:0] raw_data);
        dmem_trace_t trace;

        raw_data = 32'b0;
        if (dmem_q.size() == 0) begin
            fail_count++;
            `uvm_error("PROGRAM_SCORE", $sformatf(
                "missing dmem read instr=0x%08x addr=0x%08x", instr, addr))
            return;
        end

        trace = dmem_q.pop_front();
        if (!trace.is_read) begin
            fail_count++;
            `uvm_error("PROGRAM_SCORE", $sformatf(
                "expected dmem read but saw write instr=0x%08x addr=0x%08x",
                instr, addr))
        end
        else if (trace.addr !== addr) begin
            fail_count++;
            `uvm_error("PROGRAM_SCORE", $sformatf(
                "dmem read addr mismatch instr=0x%08x exp=0x%08x act=0x%08x",
                instr, addr, trace.addr))
        end
        else begin
            dmem_check_count++;
        end
        raw_data = trace.data;
    endfunction

    function void check_dmem_write(
        input bit [31:0] instr,
        input bit [31:0] addr,
        input bit [3:0] wstrb,
        input bit [31:0] wdata
    );
        dmem_trace_t trace;

        if (dmem_q.size() == 0) begin
            fail_count++;
            `uvm_error("PROGRAM_SCORE", $sformatf(
                "missing dmem write instr=0x%08x addr=0x%08x wstrb=0x%0x wdata=0x%08x",
                instr, addr, wstrb, wdata))
            return;
        end

        trace = dmem_q.pop_front();
        if (!trace.is_write) begin
            fail_count++;
            `uvm_error("PROGRAM_SCORE", $sformatf(
                "expected dmem write but saw read instr=0x%08x addr=0x%08x",
                instr, addr))
        end
        else if ((trace.addr !== addr) || (trace.wstrb !== wstrb) || (trace.wdata !== wdata)) begin
            fail_count++;
            `uvm_error("PROGRAM_SCORE", $sformatf(
                "dmem write mismatch instr=0x%08x exp_addr=0x%08x act_addr=0x%08x exp_wstrb=0x%0x act_wstrb=0x%0x exp_wdata=0x%08x act_wdata=0x%08x",
                instr, addr, trace.addr, wstrb, trace.wstrb, wdata, trace.wdata))
        end
        else begin
            dmem_check_count++;
        end
    endfunction

    function void execute_instr(input bit [31:0] instr, inout bit [31:0] pc);
        bit [6:0] opcode;
        bit [4:0] rd;
        bit [4:0] rs1;
        bit [4:0] rs2;
        bit [31:0] imm;
        bit [31:0] addr;
        bit [31:0] raw_data;

        opcode = instr[6:0];
        rd = instr[11:7];
        rs1 = instr[19:15];
        rs2 = instr[24:20];

        case (opcode)
            7'b0110011: begin
                push_expected(instr, pc, rd, calc_r_type(instr));
                pc = pc + 4;
            end

            7'b0010011: begin
                push_expected(instr, pc, rd, calc_i_type(instr));
                pc = pc + 4;
            end

            7'b0000011: begin
                imm = sext({20'b0, instr[31:20]}, 12);
                addr = exp_regs[rs1] + imm;
                check_dmem_read(instr, addr, raw_data);
                push_expected(instr, pc, rd, load_value(instr, raw_data));
                pc = pc + 4;
            end

            7'b0100011: begin
                imm = sext({20'b0, instr[31:25], instr[11:7]}, 12);
                addr = exp_regs[rs1] + imm;
                check_dmem_write(instr, addr, store_wstrb(instr), exp_regs[rs2]);
                pc = pc + 4;
            end

            7'b1100011: begin
                imm = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
                pc = branch_taken(instr) ? (pc + imm) : (pc + 4);
            end

            7'b1101111: begin
                imm = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
                push_expected(instr, pc, rd, pc + 4);
                pc = pc + imm;
            end

            7'b1100111: begin
                imm = sext({20'b0, instr[31:20]}, 12);
                push_expected(instr, pc, rd, pc + 4);
                pc = (exp_regs[rs1] + imm) & ~32'h0000_0001;
            end

            7'b0110111: begin
                push_expected(instr, pc, rd, {instr[31:12], 12'b0});
                pc = pc + 4;
            end

            7'b0010111: begin
                push_expected(instr, pc, rd, pc + {instr[31:12], 12'b0});
                pc = pc + 4;
            end

            default: begin
                pc = pc + 4;
            end
        endcase

        exp_regs[0] = 32'b0;
    endfunction

    function void build_expected_queue();
        bit [31:0] ref_pc;
        bit [31:0] instr;

        if (!regs_loaded) begin
            load_initial_regs();
        end

        ref_pc = 32'b0;
        while ((instr_q.size() != 0) && (exp_q.size() < act_q.size())) begin
            instr = instr_q.pop_front();
            execute_instr(instr, ref_pc);
        end
    endfunction

    virtual function void write_instr(instr_item item);
        super.write_instr(item);
        if (item == null) return;
        instr_q.push_back(item.instr);
    endfunction

    virtual function void write_commit(probe_item item);
        reg_write_t act;

        super.write_commit(item);
        if (item == null) return;

        act.rd = item.rd_addr;
        act.value = item.rd_value;
        act.instr = 32'b0;
        act.pc = item.pc;
        act_q.push_back(act);
    endfunction

    virtual function void write_dmem(dmem_item item);
        dmem_trace_t trace;

        super.write_dmem(item);
        if (item == null) return;

        trace.is_read = item.is_read;
        trace.is_write = item.is_write;
        trace.addr = item.addr;
        trace.wstrb = item.wstrb;
        trace.data = item.data;
        trace.wdata = item.wdata;
        dmem_q.push_back(trace);
    endfunction

    virtual function void check_phase(uvm_phase phase);
        reg_write_t exp;
        reg_write_t act;

        super.check_phase(phase);
        build_expected_queue();

        while ((exp_q.size() != 0) && (act_q.size() != 0)) begin
            exp = exp_q.pop_front();
            act = act_q.pop_front();
            if (act.rd !== exp.rd) begin
                fail_count++;
                `uvm_error("PROGRAM_SCORE", $sformatf(
                    "rd mismatch pc=0x%08x instr=0x%08x exp=x%0d act=x%0d",
                    exp.pc, exp.instr, exp.rd, act.rd))
            end
            else if ((exp.rd != 5'd0) && (act.value !== exp.value)) begin
                fail_count++;
                `uvm_error("PROGRAM_SCORE", $sformatf(
                    "data mismatch pc=0x%08x instr=0x%08x rd=x%0d exp=0x%08x act=0x%08x",
                    exp.pc, exp.instr, exp.rd, exp.value, act.value))
            end
            else begin
                pass_count++;
            end
        end

        missing_count = exp_q.size();
        extra_count = act_q.size();

        while (exp_q.size() != 0) begin
            exp = exp_q.pop_front();
            `uvm_error("PROGRAM_SCORE", $sformatf(
                "missing commit pc=0x%08x instr=0x%08x rd=x%0d exp=0x%08x",
                exp.pc, exp.instr, exp.rd, exp.value))
        end

        while (act_q.size() != 0) begin
            act = act_q.pop_front();
            `uvm_error("PROGRAM_SCORE", $sformatf(
                "unexpected commit rd=x%0d value=0x%08x probe_pc=0x%08x",
                act.rd, act.value, act.pc))
        end

        while (dmem_q.size() != 0) begin
            dmem_trace_t trace;
            trace = dmem_q.pop_front();
            `uvm_error("PROGRAM_SCORE", $sformatf(
                "unexpected dmem access is_read=%0d is_write=%0d addr=0x%08x",
                trace.is_read, trace.is_write, trace.addr))
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("PROGRAM_SCORE", $sformatf(
            "pass=%0d fail=%0d missing=%0d extra=%0d dmem_checked=%0d",
            pass_count, fail_count, missing_count, extra_count,
            dmem_check_count), UVM_NONE)
    endfunction

endclass
