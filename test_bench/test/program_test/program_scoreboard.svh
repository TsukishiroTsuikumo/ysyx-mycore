class program_scoreboard extends mycore_scoreboard;
    `uvm_component_utils(program_scoreboard)

    typedef struct packed {
        bit [31:0] pc;
        bit [31:0] instr;
    } retire_t;

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
        bit [31:0] instr;
        bit [31:0] pc;
    } dmem_trace_t;

    retire_t     act_retire_q[$];
    reg_write_t  act_q[$];
    reg_write_t  exp_q[$];
    dmem_trace_t act_dmem_q[$];

    int unsigned pass_count;
    int unsigned fail_count;
    int unsigned missing_count;
    int unsigned extra_count;
    int unsigned dmem_check_count;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void push_expected_commit(
        input bit [31:0] instr,
        input bit [31:0] pc,
        input bit [4:0]  rd,
        input bit [31:0] value
    );
        reg_write_t exp;

        exp.rd = rd;
        exp.value = (rd == 5'd0) ? 32'b0 : value;
        exp.instr = instr;
        exp.pc = pc;
        exp_q.push_back(exp);
    endfunction

    function void check_expected_dmem(
        input bit [31:0] instr,
        input bit [31:0] pc,
        input bit        is_read,
        input bit        is_write,
        input bit [31:0] addr,
        input bit [3:0]  wstrb,
        input bit [31:0] wdata,
        input bit [31:0] rdata
    );
        dmem_trace_t act;

        if (act_dmem_q.size() == 0) begin
            fail_count++;
            `uvm_error("PROGRAM_SCORE", $sformatf(
                "missing DUT dmem access pc=0x%08x instr=0x%08x exp_read=%0d exp_write=%0d exp_addr=0x%08x",
                pc, instr, is_read, is_write, addr))
            return;
        end

        act = act_dmem_q.pop_front();
        if ((act.is_read !== is_read) || (act.is_write !== is_write) ||
            (act.addr !== addr)) begin
            fail_count++;
            `uvm_error("PROGRAM_SCORE", $sformatf(
                "dmem access mismatch pc=0x%08x instr=0x%08x exp_read=%0d act_read=%0d exp_write=%0d act_write=%0d exp_addr=0x%08x act_addr=0x%08x",
                pc, instr, is_read, act.is_read, is_write, act.is_write, addr, act.addr))
            return;
        end

        if (is_write && ((act.wstrb !== wstrb) || (act.wdata !== wdata))) begin
            fail_count++;
            `uvm_error("PROGRAM_SCORE", $sformatf(
                "dmem write mismatch pc=0x%08x instr=0x%08x exp_addr=0x%08x act_addr=0x%08x exp_wstrb=0x%0x act_wstrb=0x%0x exp_wdata=0x%08x act_wdata=0x%08x",
                pc, instr, addr, act.addr, wstrb, act.wstrb, wdata, act.wdata))
            return;
        end

        if (is_read && (act.data !== rdata)) begin
            fail_count++;
            `uvm_error("PROGRAM_SCORE", $sformatf(
                "dmem read data mismatch pc=0x%08x instr=0x%08x addr=0x%08x exp=0x%08x act=0x%08x",
                pc, instr, addr, rdata, act.data))
            return;
        end

        dmem_check_count++;
    endfunction

    function void build_expected_queue_from_cmodel();
        int unsigned ok;
        int unsigned retire;
        int unsigned commit;
        int unsigned pc;
        int unsigned instr;
        int unsigned rd;
        int unsigned rd_value;
        int unsigned dmem_valid;
        int unsigned dmem_is_read;
        int unsigned dmem_is_write;
        int unsigned dmem_addr;
        int unsigned dmem_wstrb;
        int unsigned dmem_wdata;
        int unsigned dmem_rdata;
        retire_t act_retire;

        while (act_retire_q.size() != 0) begin
            act_retire = act_retire_q.pop_front();
            ok = cmodel_step(
                retire,
                commit,
                pc,
                instr,
                rd,
                rd_value,
                dmem_valid,
                dmem_is_read,
                dmem_is_write,
                dmem_addr,
                dmem_wstrb,
                dmem_wdata,
                dmem_rdata
            );

            if (!ok || !retire) begin
                fail_count++;
                `uvm_error("PROGRAM_SCORE", $sformatf(
                    "C model failed to retire for DUT pc=0x%08x instr=0x%08x",
                    act_retire.pc, act_retire.instr))
                return;
            end

            if ((pc !== act_retire.pc) || (instr !== act_retire.instr)) begin
                fail_count++;
                `uvm_error("PROGRAM_SCORE", $sformatf(
                    "retire mismatch exp_pc=0x%08x act_pc=0x%08x exp_instr=0x%08x act_instr=0x%08x",
                    pc, act_retire.pc, instr, act_retire.instr))
            end

            if (dmem_valid) begin
                check_expected_dmem(
                    instr,
                    pc,
                    dmem_is_read[0],
                    dmem_is_write[0],
                    dmem_addr,
                    dmem_wstrb[3:0],
                    dmem_wdata,
                    dmem_rdata
                );
            end

            if (commit) begin
                push_expected_commit(instr, pc, rd[4:0], rd_value);
            end
        end
    endfunction

    virtual function void write_instr(instr_item item);
        super.write_instr(item);
    endfunction

    virtual function void write_commit(probe_item item);
        retire_t act_retire;
        reg_write_t act;

        super.write_commit(item);
        if (item == null) return;

        if (item.retire) begin
            act_retire.pc = item.pc;
            act_retire.instr = item.instr;
            act_retire_q.push_back(act_retire);
        end

        if (item.commit) begin
            act.rd = item.rd_addr;
            act.value = item.rd_value;
            act.instr = item.instr;
            act.pc = item.pc;
            act_q.push_back(act);
        end
    endfunction

    virtual function void write_dmem(fetch_data_item item);
        dmem_trace_t act;

        super.write_dmem(item);
        if (item == null) return;

        act.is_read = item.is_read;
        act.is_write = item.is_write;
        act.addr = item.addr;
        act.wstrb = item.wstrb;
        act.data = item.data;
        act.wdata = item.wdata;
        act.instr = 32'b0;
        act.pc = 32'b0;
        act_dmem_q.push_back(act);
    endfunction

    virtual function void check_phase(uvm_phase phase);
        reg_write_t exp;
        reg_write_t act;

        super.check_phase(phase);
        build_expected_queue_from_cmodel();

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
            fail_count++;
            `uvm_error("PROGRAM_SCORE", $sformatf(
                "missing commit pc=0x%08x instr=0x%08x rd=x%0d exp=0x%08x",
                exp.pc, exp.instr, exp.rd, exp.value))
        end

        while (act_q.size() != 0) begin
            act = act_q.pop_front();
            fail_count++;
            `uvm_error("PROGRAM_SCORE", $sformatf(
                "unexpected commit rd=x%0d value=0x%08x probe_pc=0x%08x",
                act.rd, act.value, act.pc))
        end

        while (act_dmem_q.size() != 0) begin
            dmem_trace_t trace;
            trace = act_dmem_q.pop_front();
            fail_count++;
            `uvm_error("PROGRAM_SCORE", $sformatf(
                "unexpected DUT dmem access is_read=%0d is_write=%0d addr=0x%08x",
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
