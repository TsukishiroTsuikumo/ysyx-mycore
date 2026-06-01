class dcache_sequencer extends uvm_sequencer #(dcache_item);

    `uvm_component_utils(dcache_sequencer)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

endclass
