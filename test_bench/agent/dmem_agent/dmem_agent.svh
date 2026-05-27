class dmem_agent extends uvm_agent;

    `uvm_component_utils(dmem_agent)

    dmem_sequencer sequencer;
    dmem_driver driver;
    dmem_monitor monitor;

    uvm_active_passive_enum is_active;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(uvm_active_passive_enum)::get(this, "", "is_active", is_active)) begin
            is_active = UVM_ACTIVE;
        end
        void'($value$plusargs("DMEM_AGENT_ACTIVE=%b", is_active));

        if(is_active == UVM_ACTIVE) begin
            `uvm_info("DMEM_AGENT", "Agent is active", UVM_LOW)
            sequencer = dmem_sequencer::type_id::create("sequencer", this);
            driver = dmem_driver::type_id::create("driver", this);
        end
        else begin
            `uvm_info("DMEM_AGENT", "Agent is passive", UVM_LOW)
        end
        monitor = dmem_monitor::type_id::create("monitor", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if(is_active == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass
