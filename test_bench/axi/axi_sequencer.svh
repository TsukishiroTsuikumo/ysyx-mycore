`ifndef YSYX_AXI_SEQUENCER_SVH
`define YSYX_AXI_SEQUENCER_SVH

class axi_sequencer #(
    int unsigned ADDR_WIDTH  = 32,
    int unsigned DATA_WIDTH  = 32,
    int unsigned ID_WIDTH    = 2,
    int unsigned USER_WIDTH  = 1,
    int unsigned OWNER_WIDTH = 1
) extends uvm_sequencer #(
    axi_transaction #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    )
);

    typedef axi_sequencer #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH, OWNER_WIDTH
    ) this_type;

    `uvm_component_param_utils(this_type)

    function new(string name = "axi_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass

`endif
