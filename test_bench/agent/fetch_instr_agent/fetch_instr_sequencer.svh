class fetch_instr_sequencer extends uvm_sequencer #(instr_item);

  `uvm_component_utils(fetch_instr_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass
