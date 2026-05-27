class mycore_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(mycore_scoreboard)

    uvm_analysis_imp_instr  #(instr_item, mycore_scoreboard) instr_imp;
    uvm_analysis_imp_commit #(probe_item, mycore_scoreboard) commit_imp;
    uvm_analysis_imp_dmem   #(dmem_item,  mycore_scoreboard) dmem_ap;

    int unsigned instr_count;
    int unsigned commit_count;
    int unsigned dmem_count;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        instr_imp  = new("instr_imp", this);
        commit_imp = new("commit_imp", this);
        dmem_ap    = new("dmem_ap", this);
    endfunction

    virtual function void write_instr(instr_item item);
        if (item != null) begin
            instr_count++;
        end
    endfunction

    virtual function void write_commit(probe_item item);
        if (item != null) begin
            commit_count++;
        end
    endfunction

    virtual function void write_dmem(dmem_item item);
        if (item != null) begin
            dmem_count++;
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCORE", $sformatf("instr=%0d commit=%0d dmem=%0d",
                  instr_count, commit_count, dmem_count), UVM_LOW)
    endfunction

endclass
