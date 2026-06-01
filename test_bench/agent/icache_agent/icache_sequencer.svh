class icache_sequencer extends uvm_sequencer #(icache_item);

    `uvm_component_utils(icache_sequencer)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
endclass
