class mycore_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(mycore_scoreboard)

    uvm_analysis_imp #(mycore_item, mycore_scoreboard) mon_imp;
    virtual state_probe_if probe_vif;

    int unsigned instr_count;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        mon_imp = new("mon_imp", this);
        instr_count = 0;
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual state_probe_if)::get(this, "", "vif", probe_vif)) begin
            `uvm_info("NOVIF", "state_probe_if not set; running without reg checks", UVM_LOW)
        end
    endfunction

    function void write(mycore_item item);
        if (item == null) begin
            `uvm_warning("SCORE", "null item received")
        return;
        end
        instr_count++;
        `uvm_info("SCORE", $sformatf("instr %0d pm_rd_in=0x%08x",
                                    instr_count, item.pm_rd_in), UVM_LOW)
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCORE", $sformatf("total instrs=%0d", instr_count), UVM_LOW)
    endfunction

endclass
