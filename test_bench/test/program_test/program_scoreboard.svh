class program_scoreboard extends mycore_scoreboard;
    `uvm_component_utils(program_scoreboard)

    typedef struct packed {
        bit [31:0]      pc;
        bit [31:0]      instr;
        bit [31:0]      addr;
        bit             is_read;
        bit [31:0]      rdata;
        bit             is_write;
        bit [3:0]       wstrb;
        bit [31:0]      wdata;
    } dmem_trace_t;

    typedef struct packed {
        bit [31:0]      pc;
        bit [31:0]      instr;
        bit             commit_valid;
        bit  [4:0]      rd_addr;
        bit [31:0]      rd_data;
        dmem_trace_t    dmem_trace;
    } retire_trace_t;

    retire_trace_t  act_q[$];
    retire_trace_t  exp_q[$];
    dmem_trace_t    act_dmem_q[$];

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void write_retire(probe_item item);
        retire_trace_t act;

        super.write_retire(item);
        if (item == null) return;
        if (!item.retire) return;

        act.pc = item.pc;
        act.instr = item.instr;
        act.commit_valid = item.commit;
        act.rd_addr = item.rd_addr;
        act.rd_data = item.rd_value;
        act.dmem_trace = '{default: '0};

        act_q.push_back(act);
    endfunction

    virtual function void write_dmem(fetch_data_item item);
        dmem_trace_t act;

        super.write_dmem(item);
        if (item == null) return;

        act.is_read = item.is_read;
        act.is_write = item.is_write;
        act.addr = item.addr;
        act.wstrb = item.wstrb;
        act.rdata = item.rdata;
        act.wdata = item.wdata;
        act.instr = item.instr;
        act.pc = item.pc;
        act_dmem_q.push_back(act);
    endfunction

    function void merge_dmem_trace();
        int unsigned idx = 0;
        bit [6:0] opcode;
        for(int unsigned i = 0; i < act_q.size(); i++) begin
            opcode = act_q[i].instr[6:0];
            if ((opcode == 7'b0000011) || (opcode == 7'b0100011)) begin
                if (idx < act_dmem_q.size()) begin
                    // Associate scalar memory transactions with ordered
                    // load/store retirement. The monitor therefore needs no
                    // implementation-specific pipeline hierarchy.
                    act_q[i].dmem_trace = act_dmem_q[idx];
                    act_q[i].dmem_trace.pc = act_q[i].pc;
                    act_q[i].dmem_trace.instr = act_q[i].instr;
                    idx++;
                end
            end
        end
    endfunction

    virtual function void write_exp_retire_trace;
        int unsigned pc;
        int unsigned instr;
        int unsigned commit_valid;
        int unsigned rd_addr;
        int unsigned rd_data;
        int unsigned addr;
        int unsigned is_read;
        int unsigned rdata;
        int unsigned is_write;
        int unsigned wstrb;
        int unsigned wdata;

        int unsigned size = act_q.size();
        int unsigned ok;

        while (size != 0) begin
            ok = cmodel_step(
                pc,
                instr,
                commit_valid,
                rd_addr,
                rd_data,
                addr,
                is_read,
                rdata,
                is_write,
                wstrb,
                wdata
            );

            if(ok) begin
                retire_trace_t exp = '{default: '0};
                exp.pc = pc;
                exp.instr = instr;
                exp.commit_valid = commit_valid[0];
                exp.rd_addr = rd_addr[4:0];
                exp.rd_data = rd_data;
                exp.dmem_trace.pc = pc;
                exp.dmem_trace.addr = addr;
                exp.dmem_trace.instr = instr;
                exp.dmem_trace.is_read = is_read[0];
                exp.dmem_trace.rdata = rdata;
                exp.dmem_trace.is_write = is_write[0];
                exp.dmem_trace.wstrb = wstrb[3:0];
                exp.dmem_trace.wdata = wdata;

                exp_q.push_back(exp);
            end
            else begin
                `uvm_error("PROGRAM_SCORE", "C model failed to step")
            end

            size--;
        end
    endfunction

    int unsigned pass_count;
    int unsigned fail_count;
    int unsigned missing_count;
    int unsigned extra_count;

    virtual function void check_phase(uvm_phase phase);
        retire_trace_t exp;
        retire_trace_t act;

        super.check_phase(phase);
        merge_dmem_trace();
        write_exp_retire_trace();

        while ((exp_q.size() != 0) && (act_q.size() != 0)) begin
            exp = exp_q.pop_front();
            act = act_q.pop_front();

            if (act.pc !== exp.pc) begin
                fail_count++;
                `uvm_error("PROGRAM_SCORE", $sformatf(
                    "pc mismatch exp=0x%08x act=0x%08x",
                    exp.pc, act.pc))
                    continue;
            end
            else if (act.instr !== exp.instr) begin
                fail_count++;
                `uvm_error("PROGRAM_SCORE", $sformatf(
                    "instr mismatch pc=0x%08x exp=0x%08x act=0x%08x",
                    exp.pc, exp.instr, act.instr))
                continue;
            end
            else if (act.commit_valid !== exp.commit_valid) begin
                    fail_count++;
                    `uvm_error("PROGRAM_SCORE", $sformatf(
                        "commit mismatch pc=0x%08x instr=0x%08x exp=%0d act=%0d",
                        exp.pc, exp.instr, exp.commit_valid, act.commit_valid))
                continue;
            end
            else begin
                
                if (act.dmem_trace.is_read !== exp.dmem_trace.is_read) begin // memory access type check
                    fail_count++;
                    `uvm_error("PROGRAM_SCORE", $sformatf(
                        "dmem_read mismatch pc=0x%08x instr=0x%08x exp=%0d act=%0d",
                        exp.pc, exp.instr, exp.dmem_trace.is_read, act.dmem_trace.is_read))
                    continue;
                end
                else if (act.dmem_trace.is_write !== exp.dmem_trace.is_write) begin
                    fail_count++;
                    `uvm_error("PROGRAM_SCORE", $sformatf(
                        "dmem_write mismatch pc=0x%08x instr=0x%08x exp=%0d act=%0d",
                        exp.pc, exp.instr, exp.dmem_trace.is_write, act.dmem_trace.is_write))
                    continue;
                end
                else if (act.dmem_trace.addr !== exp.dmem_trace.addr) begin
                    fail_count++;
                    `uvm_error("PROGRAM_SCORE", $sformatf(
                        "dmem_addr mismatch pc=0x%08x instr=0x%08x exp=0x%08x act=0x%08x",
                        exp.pc, exp.instr, exp.dmem_trace.addr, act.dmem_trace.addr))
                    continue;
                end
                else if (act.dmem_trace.is_read) begin
                    if (act.dmem_trace.rdata !== exp.dmem_trace.rdata) begin
                        fail_count++;
                        `uvm_error("PROGRAM_SCORE", $sformatf(
                            "read_data mismatch pc=0x%08x instr=0x%08x exp=0x%08x act=0x%08x",
                            exp.pc, exp.instr, exp.dmem_trace.rdata, act.dmem_trace.rdata))
                        continue;
                    end
                end
                else if (act.dmem_trace.is_write) begin
                    if (act.dmem_trace.wdata !== exp.dmem_trace.wdata
                        || act.dmem_trace.wstrb !== exp.dmem_trace.wstrb) begin
                        fail_count++;
                        `uvm_error("PROGRAM_SCORE", $sformatf(
                            "write_data mismatch pc=0x%08x instr=0x%08x exp_wdata=0x%08x act_wdata=0x%08x exp_wstrb=0x%08x act_wstrb=0x%08x",
                            exp.pc, exp.instr, exp.dmem_trace.wdata, act.dmem_trace.wdata, exp.dmem_trace.wstrb, act.dmem_trace.wstrb))
                        continue;
                    end
                end

                if (act.commit_valid) begin // register write check
                    if (act.rd_addr !== exp.rd_addr) begin
                        fail_count++;
                        `uvm_error("PROGRAM_SCORE", $sformatf(
                            "rd_addr mismatch pc=0x%08x instr=0x%08x exp=x%0d act=x%0d",
                            exp.pc, exp.instr, exp.rd_addr, act.rd_addr))
                        continue;
                    end
                    else if (act.rd_addr != 5'd0 && act.rd_data !== exp.rd_data) begin
                        fail_count++;
                        `uvm_error("PROGRAM_SCORE", $sformatf(
                            "rd_data mismatch pc=0x%08x instr=0x%08x rd=x%0d exp=0x%08x act=0x%08x",
                            exp.pc, exp.instr, exp.rd_addr, exp.rd_data, act.rd_data))
                        continue;
                    end
                end
            end
            pass_count++;
        end

        missing_count = exp_q.size();
        extra_count = act_q.size();

        while (exp_q.size() != 0) begin
            exp = exp_q.pop_front();
            fail_count++;
            `uvm_error("PROGRAM_SCORE", $sformatf(
                "missing commit pc=0x%08x instr=0x%08x",
                exp.pc, exp.instr))
        end

        while (act_q.size() != 0) begin
            act = act_q.pop_front();
            fail_count++;
            `uvm_error("PROGRAM_SCORE", $sformatf(
                "unexpected commit pc=0x%08x instr=0x%08x",
                act.pc, act.instr))
        end

    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("PROGRAM_SCORE", $sformatf(
            "PASS=%0d FAIL=%0d MISSING=%0d EXTRA=%0d",
            pass_count, fail_count, missing_count, extra_count), UVM_NONE)
    endfunction
    

endclass
