interface mycore_if(
    input bit clk,
    input bit reset
);
    input   logic   [31:0]  pm_rd_in;
    output  logic   [31:0]  pm_addr_out;
    output  logic           ifetch;
    input   logic   [31:0]  dm_rd_in;
    output  logic   [31:0]  dm_wr_out;
    output  logic   [31:0]  dm_addr_out;
    output  logic    [3:0]  dm_st_out;
    output  logic    [3:0]  dm_ld_out;
    input   logic           ld_valid;
    
endinterface
