interface probe_if (
    input bit clk
);

    logic        reset;
    
    // Stable two-slot retirement bus. Lane 0 occupies the low bits and is
    // always older than lane 1 when both are valid.
    logic  [1:0] retire_valid;
    logic [63:0] retire_pc;
    logic [63:0] retire_instr;
    logic  [1:0] retire_rd_write;
    logic  [9:0] retire_rd_addr;
    logic [63:0] retire_rd_data;

    logic [31:0] init_reg_value [0:31];
    logic        reg_init_done;
    logic        bus_fault_valid;
    logic        bus_fault_is_write;
    logic [31:0] bus_fault_addr;
    logic  [1:0] bus_fault_resp;
    event reg_init_request;

    task automatic request_reg_init();
        reg_init_done = 1'b0;
        -> reg_init_request;
        wait (reg_init_done == 1'b1);
    endtask
    
endinterface
