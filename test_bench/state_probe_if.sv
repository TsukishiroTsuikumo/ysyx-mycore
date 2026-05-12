interface state_probe_if(
    input bit clk,
    input bit reset
);
    logic [31:0] pm_rd_in;
    logic [31:0] pc_val;
    logic [31:0] reg_val[0:31];
    logic [31:0] init_reg_val[0:31];
    logic        w1_en;
    logic        wb_en;
    logic [4:0]  wb_addr;
    logic [31:0] wb_data;
    logic        reg_init_done;
    
endinterface
