class jp_link_scoreboard extends mycore_scoreboard;

    `uvm_component_utils(jp_link_scoreboard)

    typedef struct packed {
        bit [4:0]  rd;
        bit [31:0] value;
        bit [31:0] instr;
    } reg_write_t;

    reg_write_t act_q[$];

    int unsigned pass_count;
    int unsigned fail_count;
    int unsigned missing_count;
    int unsigned extra_count;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void write_retire(probe_item item);
        reg_write_t act;
        super.write_retire(item);
        if (item == null) return;
        if (item.commit) begin
            act.rd = item.rd_addr;
            act.value = item.rd_value;
            act.instr = item.instr;
            act_q.push_back(act);
        end
    endfunction

    virtual function void check_phase(uvm_phase phase);
        reg_write_t act;

        super.check_phase(phase);
        while (act_q.size() != 0) begin
            act = act_q.pop_front();
            if (act.rd !== 5'd1) begin
                fail_count++;
                `uvm_error("JP_LINK_SCORE", $sformatf(
                    "rd mismatch exp=x1 act=x%0d value=0x%08x",
                    act.rd, act.value))
            end
            else if ((act.value[1:0] !== 2'b00) || (act.value == 32'b0)) begin
                fail_count++;
                `uvm_error("JP_LINK_SCORE", $sformatf(
                    "invalid link value rd=x1 value=0x%08x", act.value))
            end
            else begin
                pass_count++;
            end
        end

        missing_count = 0;
        extra_count = 0;
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("JP_LINK_SCORE", $sformatf(
            "pass=%0d fail=%0d missing=%0d extra=%0d",
            pass_count, fail_count, missing_count, extra_count), UVM_NONE)
    endfunction

endclass
