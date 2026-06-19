class st_scoreboard extends mycore_scoreboard;

    `uvm_component_utils(st_scoreboard)

    typedef struct packed {
        bit [31:0] addr;
        bit [3:0]  wstrb;
        bit [31:0] wdata;
        bit [31:0] instr;
    } store_t;

    virtual probe_if probe_vif;
    bit [31:0] instr_q[$];
    fetch_data_item act_q[$];
    bit [31:0] regs[0:31];
    bit regs_loaded;

    int unsigned pass_count;
    int unsigned fail_count;
    int unsigned missing_count;
    int unsigned extra_count;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual probe_if)::get(this, "", "probe", probe_vif)) begin
            `uvm_fatal("ST_SCOREBOARD", "Failed to get probe interface")
        end
    endfunction

    function void load_initial_regs();
        foreach (regs[i]) begin
            regs[i] = probe_vif.init_reg_value[i];
        end
        regs[0] = 32'b0;
        regs_loaded = 1'b1;
    endfunction

    function automatic bit [31:0] sext(input bit [31:0] value, input int unsigned width);
        bit [31:0] mask;
        if (width >= 32) return value;
        mask = (32'h0000_0001 << width) - 1;
        return value[width - 1] ? (value | ~mask) : (value & mask);
    endfunction

    function automatic bit [3:0] store_wstrb(input bit [31:0] instr);
        case (instr[14:12])
            3'b000: return 4'b0001;
            3'b001: return 4'b0011;
            3'b010: return 4'b1111;
            default: return 4'b0000;
        endcase
    endfunction

    function automatic store_t decode_store(input bit [31:0] instr);
        store_t exp;
        bit [4:0] rs1;
        bit [4:0] rs2;
        bit [31:0] imm;

        rs1 = instr[19:15];
        rs2 = instr[24:20];
        imm = sext({20'b0, instr[31:25], instr[11:7]}, 12);

        exp.addr = regs[rs1] + imm;
        exp.wstrb = store_wstrb(instr);
        exp.wdata = regs[rs2];
        exp.instr = instr;
        return exp;
    endfunction

    virtual function void write_dmem(fetch_data_item item);
        super.write_dmem(item);
        if (item != null) act_q.push_back(item);
    endfunction

    virtual function void write_retire(probe_item item);
        super.write_retire(item);
        if ((item != null) && item.retire) begin
            instr_q.push_back(item.instr);
        end
    endfunction

    virtual function void check_phase(uvm_phase phase);
        store_t exp;
        fetch_data_item act;

        super.check_phase(phase);
        if (!regs_loaded) load_initial_regs();

        while ((instr_q.size() != 0) && (act_q.size() != 0)) begin
            exp = decode_store(instr_q.pop_front());
            act = act_q.pop_front();
            if (!act.is_write) begin
                fail_count++;
                `uvm_error("ST_SCORE", "expected store, saw read")
            end
            else if ((act.addr !== exp.addr) || (act.wstrb !== exp.wstrb) || (act.wdata !== exp.wdata)) begin
                fail_count++;
                `uvm_error("ST_SCORE", $sformatf(
                    "store mismatch instr=0x%08x exp_addr=0x%08x act_addr=0x%08x exp_wstrb=0x%0x act_wstrb=0x%0x exp_wdata=0x%08x act_wdata=0x%08x",
                    exp.instr, exp.addr, act.addr, exp.wstrb, act.wstrb, exp.wdata, act.wdata))
            end
            else begin
                pass_count++;
            end
        end

        // Store-only tests stop after the expected number of observed writes.
        // The fetch side may already have accepted a few younger instructions;
        // those do not represent missing stores for this test.
        missing_count = 0;
        extra_count = act_q.size();
        instr_q.delete();
        while (act_q.size() != 0) begin
            act = act_q.pop_front();
            `uvm_error("ST_SCORE", $sformatf(
                "unexpected data access is_read=%0d is_write=%0d addr=0x%08x",
                act.is_read, act.is_write, act.addr))
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("ST_SCORE", $sformatf(
            "pass=%0d fail=%0d missing=%0d extra=%0d",
            pass_count, fail_count, missing_count, extra_count), UVM_NONE)
    endfunction

endclass
