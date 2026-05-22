interface state_probe_if(
    input logic clk,
    input logic reset
);
    logic [31:0] instr_val;
    logic [31:0] pc_val;
    logic [31:0] reg_val[0:31];
    logic [31:0] init_reg_val[0:31];
    logic        instr_accept;
    logic        commit;
    logic [4:0]  wb_addr;
    logic [31:0] wb_data;
    logic        reg_init_done;
    event        reg_init_request;

    task automatic request_reg_init();
        reg_init_done = 1'b0;
        -> reg_init_request;
        wait (reg_init_done == 1'b1);
    endtask
    
endinterface
