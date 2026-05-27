class dmem_sequencer extends uvm_sequencer #(dmem_item);

    `uvm_component_utils(dmem_sequencer)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

endclass
