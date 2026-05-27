interface probe_if (
    input bit clk
);

    logic        reset;
    logic [31:0] pc;

    logic        commit;
    logic  [4:0] rd_addr;
    logic [31:0] rd_data;

    logic [31:0] regfile_value [0:31];
    logic [31:0] init_reg_value [0:31];
    logic        reg_init_done;

    event reg_init_request;

    task automatic request_reg_init();
        reg_init_done = 1'b0;
        -> reg_init_request;
        wait (reg_init_done == 1'b1);
    endtask
    
endinterface
