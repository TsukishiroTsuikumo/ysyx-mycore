class mycore_sequencer extend uvm_sequencer #(mycore_item);
    `uvm_component_utils(mycore_sequencer)
  
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

endclass