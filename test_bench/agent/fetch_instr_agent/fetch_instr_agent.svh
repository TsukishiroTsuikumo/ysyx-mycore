class fetch_instr_agent extends uvm_agent;
    `uvm_component_utils(fetch_instr_agent)

    fetch_instr_driver driver;
    fetch_instr_monitor monitor;
    fetch_instr_sequencer sequencer;

    uvm_active_passive_enum is_active;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);

        super.build_phase(phase);

        if(!uvm_config_db#(uvm_active_passive_enum)::get(this, "", "is_active", is_active)) begin
            is_active = UVM_ACTIVE;
        end
        void'($value$plusargs("FETCH_INSTR_AGENT_ACTIVE=%b", is_active));

        if(is_active == UVM_ACTIVE) begin
            `uvm_info("FETCH_INSTR_AGENT", "Agent is active", UVM_LOW)
            sequencer = fetch_instr_sequencer::type_id::create("sequencer", this);
            driver = fetch_instr_driver::type_id::create("driver", this);
        end
        else begin
            `uvm_info("FETCH_INSTR_AGENT", "Agent is passive", UVM_LOW)
        end
        monitor = fetch_instr_monitor::type_id::create("monitor", this);

    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if(is_active == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass
