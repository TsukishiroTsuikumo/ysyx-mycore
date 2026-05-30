class program_agent extends uvm_agent;

    `uvm_component_utils(program_agent)

    program_responder responder;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        responder = program_responder::type_id::create("responder", this);
    endfunction

endclass
