class mycore_agent extends uvm_agent;
    `uvm_component_utils(mycore_agent)

    mycore_agent_config cfg;

    mycore_sequencer sequencer;
    mycore_driver driver;
    mycore_monitor monitor;

    virtual mycore_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        monitor = mycore_monitor::type_id::create("monitor", this);

        if(!uvm_config_db#(mycore_agent_config)::get(this, "", "agent_cfg", cfg))
            `uvm_fatal("NOAGENTCFG", "agent cannot get agent_cfg")
        
        if(cfg.agent_type == UVM_ACTIVE) begin
            sequencer = mycore_sequencer::type_id::create("sequencer", this);
            driver = mycore_driver::type_id::create("driver", this);
        end
        
        if (!uvm_config_db#(virtual mycore_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "agent cannot get vif")
    
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if(cfg.agent_type == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass
