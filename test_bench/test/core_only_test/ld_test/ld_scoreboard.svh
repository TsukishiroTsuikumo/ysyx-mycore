class ld_scoreboard extends mycore_scoreboard;

    `uvm_component_utils(ld_scoreboard)

    typedef struct packed {
        bit [4:0]  rd;
        bit [31:0] value;
        bit [31:0] addr;
        bit [31:0] instr;
    } load_t;

    bit [31:0] instr_q[$];
    fetch_data_item dmem_q[$];
    load_t act_q[$];

    int unsigned pass_count;
    int unsigned fail_count;
    int unsigned missing_count;
    int unsigned extra_count;
    int unsigned dmem_checked;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function automatic bit [31:0] sext(input bit [31:0] value, input int unsigned width);
        bit [31:0] mask;
        if (width >= 32) return value;
        mask = (32'h0000_0001 << width) - 1;
        return value[width - 1] ? (value | ~mask) : (value & mask);
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

    function automatic bit [31:0] load_addr(input bit [31:0] instr);
        bit [4:0] rs1;
        bit [31:0] rs1_value;
        bit [31:0] imm;

        rs1 = instr[19:15];
        rs1_value = 32'b0;
        imm = sext({20'b0, instr[31:20]}, 12);

        // ld_item constrains rs1 to x0. Keep the decode explicit so this
        // scoreboard remains tied to the core-only load test contract.
        if (rs1 != 5'd0) begin
            `uvm_error("LD_SCORE", $sformatf(
                "ld_scoreboard only supports rs1=x0, instr=0x%08x rs1=x%0d",
                instr, rs1))
        end

        return rs1_value + imm;
    endfunction

    virtual function void write_dmem(fetch_data_item item);
        super.write_dmem(item);
        if (item != null) begin
            dmem_q.push_back(item);
        end
    endfunction

    virtual function void write_retire(probe_item item);
        load_t act;

        super.write_retire(item);
        if (item == null) return;

        if (item.retire) begin
            instr_q.push_back(item.instr);
        end

        if (item.commit) begin
            act.rd = item.rd_addr;
            act.value = item.rd_value;
            act.addr = 32'b0;
            act.instr = item.instr;
            act_q.push_back(act);
        end
    endfunction

    virtual function void check_phase(uvm_phase phase);
        bit [31:0] instr;
        bit [31:0] exp_addr;
        bit [31:0] exp_value;
        bit [4:0] exp_rd;
        fetch_data_item dmem;
        load_t act;

        super.check_phase(phase);

        while ((instr_q.size() != 0) && (dmem_q.size() != 0) && (act_q.size() != 0)) begin
            instr = instr_q.pop_front();
            dmem = dmem_q.pop_front();
            act = act_q.pop_front();

            exp_addr = load_addr(instr);
            exp_value = load_value(instr, dmem.rdata);
            exp_rd = instr[11:7];

            if (!dmem.is_read) begin
                fail_count++;
                `uvm_error("LD_SCORE", $sformatf(
                    "expected read, saw write instr=0x%08x addr=0x%08x",
                    instr, dmem.addr))
            end
            else if (dmem.addr !== exp_addr) begin
                fail_count++;
                `uvm_error("LD_SCORE", $sformatf(
                    "read addr mismatch instr=0x%08x exp=0x%08x act=0x%08x",
                    instr, exp_addr, dmem.addr))
            end
            else if (act.rd !== exp_rd) begin
                fail_count++;
                `uvm_error("LD_SCORE", $sformatf(
                    "rd mismatch instr=0x%08x exp=x%0d act=x%0d",
                    instr, exp_rd, act.rd))
            end
            else if (act.value !== exp_value) begin
                fail_count++;
                `uvm_error("LD_SCORE", $sformatf(
                    "load data mismatch instr=0x%08x rd=x%0d raw=0x%08x exp=0x%08x act=0x%08x",
                    instr, exp_rd, dmem.rdata, exp_value, act.value))
            end
            else begin
                pass_count++;
                dmem_checked++;
            end
        end

        missing_count = instr_q.size();
        extra_count = act_q.size() + dmem_q.size();

        while (instr_q.size() != 0) begin
            instr = instr_q.pop_front();
            fail_count++;
            `uvm_error("LD_SCORE", $sformatf(
                "missing load result or dmem response instr=0x%08x", instr))
        end

        while (act_q.size() != 0) begin
            act = act_q.pop_front();
            fail_count++;
            `uvm_error("LD_SCORE", $sformatf(
                "unexpected commit rd=x%0d value=0x%08x instr=0x%08x",
                act.rd, act.value, act.instr))
        end

        while (dmem_q.size() != 0) begin
            dmem = dmem_q.pop_front();
            fail_count++;
            `uvm_error("LD_SCORE", $sformatf(
                "unexpected dmem access is_read=%0d is_write=%0d addr=0x%08x",
                dmem.is_read, dmem.is_write, dmem.addr))
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("LD_SCORE", $sformatf(
            "pass=%0d fail=%0d missing=%0d extra=%0d dmem_checked=%0d",
            pass_count, fail_count, missing_count, extra_count, dmem_checked), UVM_NONE)
    endfunction

endclass
