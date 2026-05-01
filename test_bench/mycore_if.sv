interface mycore_if(
    input bit clk,
    input bit reset
);
    logic   [31:0]  pm_rd_in;
    logic   [31:0]  pm_addr_out;
    logic           ifetch;
    logic   [31:0]  dm_rd_in;
    logic   [31:0]  dm_wr_out;
    logic   [31:0]  dm_addr_out;
    logic    [3:0]  dm_st_out;
    logic    [3:0]  dm_ld_out;
    logic           ld_valid;
    
endinterface
