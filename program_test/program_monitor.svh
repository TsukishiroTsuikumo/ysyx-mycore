class program_monitor extends mycore_monitor;
    `uvm_component_utils(program_monitor)

    localparam bit [31:0] EBREAK_INSTR = 32'h0010_0073;

    uvm_event#(uvm_object) done_ev;
    bit done_seen;
    bit done_on_ebreak;
    bit done_on_store;
    bit [31:0] done_addr;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        done_seen     = 1'b0;
        done_on_ebreak = 1'b1;
        done_on_store  = 1'b1;
        done_addr      = 32'h0000_1000;
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        done_ev = uvm_event_pool::get_global("program_done");
        void'($value$plusargs("PROGRAM_DONE_ADDR=%h", done_addr));
        if ($test$plusargs("PROGRAM_NO_EBREAK_DONE")) begin
            done_on_ebreak = 1'b0;
        end
        if ($test$plusargs("PROGRAM_NO_STORE_DONE")) begin
            done_on_store = 1'b0;
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        program_item pitem;

        forever begin
            @(posedge vif.clk);

            pitem = program_item::type_id::create("pitem");
            pitem.pm_rd    = vif.pm_resp_data;
            pitem.dm_rd    = vif.dm_resp_rdata;
            pitem.ld_valid = vif.dm_resp_rvalid;
            pitem.pm_addr  = probe_vif.pc_val;
            pitem.ifetch   = probe_vif.instr_accept;
            pitem.ins_valid = probe_vif.instr_accept;
            pitem.dm_wr    = vif.dm_req_wdata;
            pitem.dm_addr  = vif.dm_req_addr;
            pitem.dm_st    = vif.dm_req_wstrb;
            pitem.dm_ld    = {3'b0, vif.dm_req_rvalid};

            act_port.write(pitem);

            if (!done_seen) begin
                if (done_on_store && (pitem.dm_st != 4'b0) && (pitem.dm_addr == done_addr)) begin
                    done_seen = 1'b1;
                    `uvm_info("PROGRAM_DONE",
                              $sformatf("done store: addr=0x%08h value=0x%08h st=0x%0h",
                                        pitem.dm_addr, pitem.dm_wr, pitem.dm_st),
                              UVM_LOW)
                    done_ev.trigger(pitem);
                end
                else if (done_on_ebreak && pitem.ifetch && pitem.ins_valid && (pitem.pm_rd == EBREAK_INSTR)) begin
                    done_seen = 1'b1;
                    `uvm_info("PROGRAM_DONE",
                              $sformatf("done ebreak: pc=0x%08h instr=0x%08h",
                                        pitem.pm_addr, pitem.pm_rd),
                              UVM_LOW)
                    done_ev.trigger(pitem);
                end
            end
        end
    endtask

endclass
