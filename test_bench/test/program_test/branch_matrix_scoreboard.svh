class branch_matrix_scoreboard extends mycore_scoreboard;
    `uvm_component_utils(branch_matrix_scoreboard)

    typedef struct packed {
        bit [4:0]  rd;
        bit [31:0] value;
    } reg_write_t;

    reg_write_t exp_q[$];
    reg_write_t act_q[$];
    bit expected_built;

    int unsigned pass_count;
    int unsigned fail_count;
    int unsigned missing_count;
    int unsigned extra_count;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void push_expected(input bit [4:0] rd, input bit [31:0] value);
        reg_write_t exp;
        exp.rd = rd;
        exp.value = value;
        exp_q.push_back(exp);
    endfunction

    function void build_expected();
        if (expected_built) begin
            return;
        end

        push_expected(5'd1,  32'h0000_0005);
        push_expected(5'd2,  32'h0000_0005);
        push_expected(5'd3,  32'h0000_0007);
        push_expected(5'd4,  32'hffff_ffff);
        push_expected(5'd5,  32'h0000_0001);

        push_expected(5'd10, 32'h0000_0101);
        push_expected(5'd11, 32'h0000_0102);
        push_expected(5'd12, 32'h0000_0103);
        push_expected(5'd13, 32'h0000_0104);
        push_expected(5'd14, 32'h0000_0105);
        push_expected(5'd15, 32'h0000_0106);
        push_expected(5'd16, 32'h0000_0107);
        push_expected(5'd17, 32'h0000_0108);
        push_expected(5'd18, 32'h0000_0109);
        push_expected(5'd19, 32'h0000_010a);
        push_expected(5'd20, 32'h0000_010b);
        push_expected(5'd21, 32'h0000_010c);

        expected_built = 1'b1;
    endfunction

    virtual function void write_commit(probe_item item);
        reg_write_t act;

        super.write_commit(item);
        if (item == null) begin
            return;
        end

        act.rd = item.rd_addr;
        act.value = item.rd_value;
        act_q.push_back(act);
    endfunction

    virtual function void check_phase(uvm_phase phase);
        reg_write_t exp;
        reg_write_t act;

        super.check_phase(phase);
        build_expected();

        while ((exp_q.size() != 0) && (act_q.size() != 0)) begin
            exp = exp_q.pop_front();
            act = act_q.pop_front();
            if (act.rd !== exp.rd) begin
                fail_count++;
                `uvm_error("BRANCH_SCORE", $sformatf(
                    "rd mismatch exp=x%0d act=x%0d act_value=0x%08x",
                    exp.rd, act.rd, act.value))
            end
            else if ((exp.rd != 5'd0) && (act.value !== exp.value)) begin
                fail_count++;
                `uvm_error("BRANCH_SCORE", $sformatf(
                    "data mismatch rd=x%0d exp=0x%08x act=0x%08x",
                    exp.rd, exp.value, act.value))
            end
            else begin
                pass_count++;
            end
        end

        missing_count = exp_q.size();
        extra_count = act_q.size();

        while (exp_q.size() != 0) begin
            exp = exp_q.pop_front();
            `uvm_error("BRANCH_SCORE", $sformatf(
                "missing commit exp rd=x%0d value=0x%08x", exp.rd, exp.value))
        end

        while (act_q.size() != 0) begin
            act = act_q.pop_front();
            if (act.rd != 5'd0) begin
                `uvm_error("BRANCH_SCORE", $sformatf(
                    "unexpected commit rd=x%0d value=0x%08x", act.rd, act.value))
            end
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("BRANCH_SCORE", $sformatf(
            "pass=%0d fail=%0d missing=%0d extra=%0d",
            pass_count, fail_count, missing_count, extra_count), UVM_NONE)
    endfunction

endclass
