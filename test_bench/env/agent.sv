class mycore_agent extend uvm_agent;
    `uvm_component_utils(mycore_agent)

    mycore_sequencer sequencer;
    mycore_driver driver;
    mycore_monitor monitor;

    virtual mycore_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = mycore_sequencer::type_id::create("sequencer", this);
        driver = mycore_driver::type_id::create("driver", this);
        monitor = mycore_monitor::type_id::create("monitor", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass