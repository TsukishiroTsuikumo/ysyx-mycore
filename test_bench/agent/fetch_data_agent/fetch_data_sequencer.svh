class fetch_data_sequencer extends uvm_sequencer #(fetch_data_item);

    `uvm_component_utils(fetch_data_sequencer)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

endclass
