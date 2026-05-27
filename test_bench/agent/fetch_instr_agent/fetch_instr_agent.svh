class fetch_instr_agent extends uvm_agent;
    `uvm_component_utils(fetch_instr_agent)

    fetch_instr_driver if_driver;
    fetch_instr_monitor if_monitor;
    fetch_instr_sequencer if_sequencer;

    uvm_active_passive_enum is_active;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);

        super.build_phase(phase);

        if(!$value$plusargs("FETCH_INSTR_AGENT_ACTIVE=%b", is_active)) begin
            is_active = UVM_ACTIVE;
        end

        if(is_active == UVM_ACTIVE) begin
            `uvm_info("FETCH_INSTR_AGENT", "Agent is active", UVM_LOW)
            if_sequencer = fetch_instr_sequencer::type_id::create("if_sequencer", this);
            if_driver = fetch_instr_driver::type_id::create("if_driver", this);
        end
        else begin
            `uvm_info("FETCH_INSTR_AGENT", "Agent is passive", UVM_LOW)
        end
        if_monitor = fetch_instr_monitor::type_id::create("if_monitor", this);

    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if(is_active == UVM_ACTIVE) begin
            if_driver.seq_item_port.connect(if_sequencer.seq_item_export);
        end
    endfunction

endclass
